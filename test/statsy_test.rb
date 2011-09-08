require 'test/unit'
require File.expand_path('../../lib/statsy', __FILE__)

class Unit < Test::Unit::TestCase
  def setup
    @transport = Statsy::Transport::Queue.new
    @client = Statsy::Client.new(@transport)
  end

  def test_increment_should_return_self
    assert_equal @client, @client.increment("foo.stat")
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

  def test_measure_should_return_self
    assert_equal @client, @client.measure("foo.stat", 100)
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

  def test_batch_should_return_self
    assert_equal @client, @client.batch { }
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

  def test_sampling_should_not_send_when_not_sampled
    @client.increment("foo.sampled", 1, 0.000001)
    assert_equal 0, @transport.size
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
