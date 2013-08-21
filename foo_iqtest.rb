#!/usr/bin/env ruby
=begin rdoc
Test of remote market interfaces.
=end

#require 'datafeed'
require 'drb/drb'
require 'iqfeed_datafeed'

quotes = DRbObject.new_with_uri($qserverURI)
historical = DRbObject.new_with_uri($hserverURI)

FMT='%F %T'

ES = "@ES#"
NQ = "@NQ#"
SPY = "SPY"
TEST = [
        :ticks_over_time,
        #:ticks_by_days,
        #:interval_over_time,
        #:interval_by_days
       ]

puts "Tests we're running: %s" %  TEST.to_s

ticks = []
historical.getTicksOverTime(ES,
                            DateTime.strptime('2011-06-13 09:30:00', FMT), 
                            DateTime.strptime('2011-06-13 09:36:00', FMT),
                            false) { |a| 
  puts "size %d: %s" % [a.size, a.join("\n")]
  ticks << a
  puts "size just added: %s" % a.size
} if TEST.member? :ticks_over_time 

ticks = []
historical.getTicksByDays(ES, 2) { |a| 
  puts "size %d: %s" % [a.size, a.join("\n")]
  ticks << a
  puts "size just added: %s" % a.size
} if TEST.member? :ticks_by_days 


ival = []
historical.getIntervalOverTime(ES, 60,
                               DateTime.strptime('2011-06-02 09:30:00', FMT), 
                               DateTime.strptime('2011-06-30 16:00:00', FMT),
                               false) { |a| 
  puts "size %d: %s" % [a.size, a.join("\n")]
  ival << a
  puts "size just added: %s" % a.size
} if TEST.member? :interval_over_time 

ival = []
historical.getIntervalByDays(ES, 60, 30) { |a| 
  puts "size %d: %s" % [a.size, a.join("\n")]
  ival << a
  puts "size just added: %s" % a.size
} if TEST.member? :interval_by_days 
  
