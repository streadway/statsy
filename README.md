# Statsy

[Cal made simple stat aggregation][cal].  And it was good.

[Etsy also made simple stat aggregation][etsy].  And it was also good.

This is a simple client.  It does 2 things, increment and measure.  Oh 3 things if you count batching too.

Usage: Default to UDP to a host in the current search domain called 'stats' on port 8125.

    client = Statsy::Client.new

Usage: Use a custom transport or change the host/port pair for UDP.

    client = Statsy::Client.new(Statsy::Transport::UDP.new("graphite.acme.com", 8125))
    client = Statsy::Client.new(Acme::Transport::Statsd) # <- you made that
    client = Statsy::Client.new(Statsy::Transport::Queue.new) # <- if you want to test stuff

Usage: Increment by 1, arbitrary integer, or arbitrary integer at a uniform random distribution

    client.increment("coffee.single-espresso")
    client.increment("coffee.single-espresso", 1)
    client.increment("coffee.single-espresso", 1, 0.5) # 50% of the time

Usage: Measure a timing stat that will calculate the mean, min, max, upper\_90 and count

    client.measure("acme.backend-runtime", response.headers["X-Runtime"].to_i)

Bonus points: Batch up many things into a fewer packets like in a shell script

    loop do
      batch_lines = 1000
      client.batch do |batch|
        $stdin.each do |log_line|
          metric, timing = parse(log_line) # <- you made that
          batch.measure metric, timing
          break if (batch_lines -= 1) <= 0
        end
      end
    end

These stats end up in your graphite interface under the top level keys. Look for them in this folders:

    stats_counts
    stats/timings
    stats

Fork it out of love.  Enjoy.

[cal]:http://code.flickr.com/blog/2008/10/27/counting-timing/
[etsy]:http://codeascraft.etsy.com/2011/02/15/measure-anything-measure-everything/


