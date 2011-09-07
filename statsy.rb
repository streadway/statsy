# Client to access statsd authored by etsy.
# https://github.com/etsy/statsd
module Statsy
  module Transport
    require 'socket'

    # UDP transport class that writes a stat per packet
    # connects on construction, doesn't handle exceptions
    class UDP < UDPSocket
      def initialize(host, port)
        super()
        connect(host, port)
      end

      def write(stat)
        send(stat, 0)
      end
    end

    # Queue transport writes for tests and batch operations
    class Queue < Array
      def write(stat)
        self.push(stat)
      end
    end
  end

  class Client
    attr_reader :transport

    # Construct a client with a given transport
    #
    # Usage:
    #   client = Statsy.new
    #   client = Statsy.new(Statsy::Transport::TCP.new("customstats", 8888))
    #
    def initialize(transport=Transport::UDP.new("stats", 8125))
      @transport = transport
    end

    # Increment a count optionally at a random sample rate
    #
    # Usage:
    #   client.increment("coffee.single-espresso")
    #   client.increment("coffee.single-espresso", 1)
    #   client.increment("coffee.single-espresso", 1, 0.5) # 50% of the time
    def increment(stat, count=1, sampling=1)
      if sampling < 1 && rand < sampling
        transport.write("%s:%d|c@%f" % [ stat, count, sampling ])
      else
        transport.write("%s:%d|c" % [ stat, count ])
      end
    end

    # Sample a timing
    #
    # Usage:
    #   client.measure("foo.backendtime", response.headers["X-Runtime"].to_i)
    #
    def measure(stat, time, sampling=1)
      if sampling >= 1 || rand < sampling
        transport.write("%s:%d|ms" % [ stat, time ])
      end
    end

    # Batch multiple transport operations, that will group any counts together
    # and send the fewest number of packets with the counts/timers optimized at
    # the end of the batch block.
    #
    # Note: this does not attempt to fit the packet size within the MTU.
    #
    # Usage:
    #   client.batch do |batch|
    #     batch.increment("foo.bar", 10)
    #     batch.measure("bat.baz", 101)
    #     batch.measure("foo.bar", 101)
    #   end
    #
    #   => write "foo.bar:10|c:333|ms"
    #   => write "bat.baz:101|ms"
    def batch
      yield self.class.new(batch = Transport::Queue.new)

      batch.inject(Hash.new { |h,k| h[k]=[] }) do |stats, stat|
        # [ "foo.bar:10|c", "foo.bar:101|ms" ]
        key, value = stat.split(':', 2)
        stats[key] << value
        stats
      end.sort.each do |pairs|
        # [ "foo.bar", [ "10|c", "101|ms" ] ]
        transport.write(pairs.flatten.join(":"))
      end
      self
    end
  end
end

if __FILE__==$0
  require 'test/unit'

  class Unit < Test::Unit::TestCase
    def setup
      @transport = Statsy::Transport::Queue.new
      @client = Statsy::Client.new(@transport)
    end

    def test_increment_should_form_single_count
      @client.increment("foo.stat")
      assert_equal "foo.stat:1|c", @transport.shift
    end

    def test_increment_should_count_by_more_than_one
      @client.increment("foo.stat", 101)
      assert_equal "foo.stat:101|c", @transport.shift
    end

    def test_increment_should_sample
      @client.increment("foo.stat", 1, 0.999999)
      assert_equal "foo.stat:1|c@0.999999", @transport.shift
    end

    def test_measure_should_form_ms_rate
      @client.measure("foo.timing", 1000)
      assert_equal "foo.timing:1000|ms", @transport.shift
    end

    def test_measure_should_sample
      @client.measure("foo.sampled.timing", 100, 0.0000001)
      assert_equal nil, @transport.shift
    end

    def test_increment_twice_should_write_twice
      @client.increment("foo.inc", 1)
      @client.increment("foo.inc", 2)
      assert_equal 2, @transport.size
      assert_equal "foo.inc:1|c", @transport.shift
      assert_equal "foo.inc:2|c", @transport.shift
    end

    def test_batch_should_write_same_as_increment
      @client.increment("foo.inc")

      @client.batch do |c|
        c.increment("foo.inc")
      end

      assert_equal 2, @transport.size
      assert_equal "foo.inc:1|c", @transport.shift
      assert_equal "foo.inc:1|c", @transport.shift
    end

    def test_batch_should_only_write_once_per_key
      @client.batch do |c|
        c.increment("foo.inc", 2)
        c.increment("foo.inc", 5)
      end

      assert_equal 1, @transport.size
      assert_equal "foo.inc:2|c:5|c", @transport.shift
    end

    def test_batch_should_group_per_key
      @client.batch do |c|
        c.increment("foo.inc", 2)
        c.increment("bar.inc", 3)
        c.increment("foo.inc", 5)
        c.increment("bar.inc", 7)
      end

      assert_equal 2, @transport.size
      assert_equal "bar.inc:3|c:7|c", @transport.shift
      assert_equal "foo.inc:2|c:5|c", @transport.shift
    end

    def test_batch_should_mix_increment_with_measure_per_key_in_sorted_order
      @client.batch do |c|
        c.increment("foo.inc", 2)
        c.increment("bar.inc", 3)
        c.measure("foo.inc", 500)
        c.measure("bar.inc", 700)
      end

      assert_equal 2, @transport.size
      assert_equal "bar.inc:3|c:700|ms", @transport.shift
      assert_equal "foo.inc:2|c:500|ms", @transport.shift
    end

    def test_batch_should_be_nestable
      @client.batch do |c1|
        c1.increment("foo.inc", 2)
        c1.measure("bar.inc", 700)
        c1.batch do |c2|
          c2.increment("foo.inc", 9)
          c2.measure("bar.inc", 900)
        end
        c1.measure("foo.inc", 500)
        c1.increment("bar.inc", 3)
      end

      assert_equal 2, @transport.size
      assert_equal "bar.inc:700|ms:900|ms:3|c", @transport.shift
      assert_equal "foo.inc:2|c:9|c:500|ms", @transport.shift
    end
  end
end
