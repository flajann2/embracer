#!/usr/bin/env ruby

require "optparse"
require "eostruct"
require "mongo"
require "pp"
require 'iqfeed_datafeed'

###################################
# Constants
SECS_IN_DAY = 3600 * 24

historical = DRbObject.new_with_uri($hserverURI)

###################################
# Options parsing
$gopts = OpenStruct.new

# Standard Options
$gopts.verbose = false
$gopts.debug = false
$gopts.warn = true
$gopts.noop = false
$gopts.days = 20

OptionParser.new do |opts|
  opts.banner = %{
Usage: ticketfetch [options]

tickfetch -- fetch ticks from IQFeed and store them in  Mongo market collections
}
  opts.on("-v",
          "--[no-]verbose",
          "Verbose output to stdout") { |v| $gopts.verbose = v  }
  opts.on("-d", "--debug", "Debug output (extensive)") { |v| $gopts.debug = v }
  opts.on("-w", "--[no-]warn", "Warnings (default #{$gopts.warn})") { |v| $gopts.warn = v }
  opts.on("-D", "--days DAYS", "Number of days (default #{$gopts.days})") { |v| $gopts.days = v.to_i }
end.parse!

symbols = ARGV

$gopts.etime = DateTime.now
$gopts.btime = $gopts.etime - $gopts.days

puts "Grab %d day(s) of tick data for %s" % [$gopts.days, symbols]

mdb = Mongo::Connection.new("ganymede.local").db("market")
########################################################################
## Set up the Mongo market.market to receive the tick data.
########################################################################
mdb[:market].ensure_index([
                           [:symbol, Mongo::ASCENDING],
                           [:stamp, Mongo::ASCENDING],
                           [:tick_id, Mongo::ASCENDING]
                          ], unique: true, dropDups: true)

########################################################################
## Set up the Mongo market.symbols to receive the symbols loaded.
########################################################################
mdb[:symbols].ensure_index([[:symbol, Mongo::ASCENDING]], unique: true, dropDups: true)

########################################################################
## Grab data!!!
########################################################################

symbols.each { |symbol|
  puts "### Grabbing %s" % symbol
  msym = EOStruct.create_eos
  msym.symbol = symbol
  msym.stamp = sym_begin = Time.now
  mdb[:symbols].update(msym.to_doc, upsert: true)

  historical.getTicksOverTime(symbol, $gopts.btime, $gopts.etime, false) { |a|
    block_begin = Time.now
    puts "  Got %d ticks of %s ending with %s" % [a.count, symbol, a[-1][:stamp]] if $gopts.verbose
    a.each { |tick| 
      pp tick if $gopts.debug
      begin
        mdb[:market].insert(tick, upsert: true)
      rescue Mongo::OperationFailure => e
        pp e if $gopts.debug
      end
    } 
    block_time = Time.now - block_begin
    puts "  %d ticks took %d seconds to process." % [a.count, block_time] if $gopts.verbose
  }
  sym_time = Time.now - sym_begin
  puts "%s took %d seconds." % [symbol, sym_time]
}
