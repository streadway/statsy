# Client to access statsd service authored by etsy. Yay etsy!
# https://github.com/etsy/statsd
module Statsy
  VERSION="0.1.1"

  module Transport
    require 'socket'

    # Atomically send a Statsd encoded message to the service
    # only call once per packet
    module Interface
      def write(stat); end
    end

    # UDP transport class that writes a stat per packet
    # connects on construction, doesn't handle exceptions
    class UDP < UDPSocket
      include Interface

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
      include Interface

      def write(stat)
        self.push(stat)
      end
    end
  end

  class Client
    # Construct a client with a given transport that implements
    # Transport::Interface
    #
    # Usage:
    #   client = Statsy::Client.new
    #   client = Statsy::Client.new(Statsy::Transport::UDP.new("custom", 8888))
    #
    def initialize(transport=Transport::UDP.new("stats", 8125))
      @transport = transport
    end

    # Increment a count optionally at a random sample rate.  These keys will
    # live under the stats and stats_counts keys.
    #
    # Usage:
    #   client.increment("coffee.single-espresso")
    #   client.increment("coffee.single-espresso", 1)
    #   client.increment("coffee.single-espresso", 1, 0.5) # 50% of the time
    #
    def increment(stat, count=1, sampling=1)
      write(stat, count, 'c', sampling)
      self
    end

    # Sample a timing.  The units of the timing are up to you and your
    # consumers, milliseconds is common.
    #
    # Including the units in the key name will help communicate the units to
    # consumers of these measurements.
    #
    # The statistics will be aggregated over the sampling period configured in
    # your statsd.  By default this is every 10 seconds.
    #
    # In graphite, these reports will end up under the stats.timings key.
    #
    # Usage:
    #   client.measure("foo.backendtime", response.headers["X-Runtime"].to_i)
    #
    # Produces the statistics found per sampling interval.
    #   stats.timings.foo.backendtime.count
    #   stats.timings.foo.backendtime.lower
    #   stats.timings.foo.backendtime.mean_90
    #   stats.timings.foo.backendtime.upper
    #   stats.timings.foo.backendtime.upper_90
    #
    def measure(stat, time, sampling=1)
      write(stat, time, 'ms', sampling)
      self
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
    #
    def batch
      yield self.class.new(batch = Transport::Queue.new)

      batch.inject(Hash.new { |h,k| h[k]=[] }) do |stats, stat|
        # [ "foo.bar:10|c", "foo.bar:101|ms" ]
        key, value = stat.split(':', 2)
        stats[key] << value
        stats
      end.sort.each do |pairs|
        # [ "foo.bar", [ "10|c", "101|ms" ] ]
        @transport.write(pairs.flatten.join(":"))
      end
      self
    end

  private
    def write(stat, value, modifier, sampling)
      if sampling < 1
        if Kernel.rand < sampling
          @transport.write("%s:%d|%s@%f" % [ stat, value, modifier, sampling ])
        end
      else
        @transport.write("%s:%d|%s" % [ stat, value, modifier ])
      end
    end
  end
end
