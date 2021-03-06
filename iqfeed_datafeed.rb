#!/usr/bin/env ruby
=begin rdoc
=IQFeed Datafeed $Rev: 1121 $

Currently, this is set up for IQFeedQuotes and IQFeedHistorical.
=end

require 'datafeed'
require 'socket'
require 'date'
require 'time'
require 'eostruct'

$SERVER_MODE = __FILE__ == $0

$IQFEED_HOST = "localhost"
$IQFEED_LI_PORT = 5009
$IQFEED_LII_PORT = 5009
$IQFEED_HISTORICAL_PORT = 9100
$IQFEED_ADMIN_PORT = 9300

# If we are using these addresses from code running on
# different machines, we are going to have to substitute
# 'localhost' with the address of the actual server!!!!
$qserverURI = "druby://localhost:#{DF_PORT_QUOTES}"
$hserverURI = "druby://localhost:#{DF_PORT_HISTORICAL}"

MAXDATAPOINTS = 12000000 # some arbitrarily large number!
CHUNK = 20000 # how many rows to collect before calling the block

# Response markers
ENDMSG = '!ENDMSG!'

# Commands
HTD = 'HTD' # Historical Tick Days
HTT = 'HTT' # Historical Tick Time (startTime to endTime)
HID = 'HID' # Historical Interval Days
HIT = 'HIT' # Historical Interval Time (startTime to endTime)
# Repsonse codes
R_ERR = 'E' # Error, throw an exception here

# Miscellaneous
FDT = "%Y%m%d %H%M%S" # strftime format string for queries
FMT = '%F %T'

module Datafeed # reopen
  class IQFeedException < DatafeedException
  end

  class IQFeedQuotes < QuoteFeed
  end

  class IQFeedHistorical < Historical
    @@TICK = [
              [:stamp, lambda {|dt| Time.strptime dt, FMT }],
              [:last, lambda {|l| l.to_f}],
              [:size, lambda {|ls| ls.to_i}],
              [:volume, lambda {|v| v.to_i}],
              [:bid, lambda {|b| b.to_f}],
              [:ask, lambda {|a| a.to_f}],
              [:tick_id, lambda {|tid| tid.to_i}],
              [:reserved1, lambda {|r| r}],
              [:reserved2, lambda {|r| r}],
              [:basis, lambda {|c| c}], # Basis For Last Character. 
             ]

    @@HIST = [
              [:stamp, lambda {|dt| Time.strptime dt, FMT }],
              [:high, lambda {|l| l.to_f}],
              [:low, lambda {|l| l.to_f}],
              [:open, lambda {|l| l.to_f}],
              [:close, lambda {|l| l.to_f}],
              [:volume, lambda {|v| v.to_i}],
              [:period_volume, lambda {|v| v.to_i}],
             ]
    # This needs to be initialized on the same server DTN is running on.
    def initialize
      # we create this particular socket connection just to keep it open
      @soc = dtnsoc
    end
    
    protected
    # Create a new socket connection to the DTN server.
    def dtnsoc
      TCPSocket.open($IQFEED_HOST, $IQFEED_HISTORICAL_PORT)
    end
    

    # Get the response data, terminates in a ENDMSG
    def getResponse(soc, &block)
      data = []
      while line = soc.gets
        #puts line
        r = line.chop.split ','
        if r[0] == R_ERR
          puts "Error detected: %s" % line
          raise IQFeedException.new(r[1]) 
        end
        if r[0] == ENDMSG
          block.(data) unless block.nil?
          puts "End of Data Detected: %s" % r
          break
        end
        data << r
        unless block.nil? or data.size < CHUNK
          block.(data)
          data = []
        end
      end
      if block.nil?
        data
      else
        nil
      end
    end

    public
    # Fetch historical ticks from IQFeed.
    # Fetch ticks based either on start and end times, or on number of days
    # from now.
    def brokerFetchTicks(symbol, days=nil, startTime=nil, endTime=nil, eos=true, &block)
      puts "brokerFetchTicks() for %s" % symbol
      soc = dtnsoc
      if days
        soc.puts [HTD, symbol,days, nil, nil, nil,1].join ','
      elsif startTime and endTime
        cmd = [HTT, symbol, 
                  startTime.strftime(FDT), 
                  endTime.strftime(FDT), nil, nil, nil, 1].join ','
        puts "Time %s to %s, cmd = %s" % [startTime, endTime, cmd]
        soc.puts cmd
      else # parameter problem
        raise IQFeedException.new("Parameter Error. Either days or start/end time must be given")
      end
      getResponse(soc) { |d|
        block.(d.map { |r|
                 h = Hash[r.zip(@@TICK).map { |v, (sym, func)| [sym, func.(v)]}]
                 h[:symbol] = symbol.to_sym
                 h = h.to_eos if eos
                 h
               })
      }
    end

    # Fetch historical intervals from IQFeed.
    #
    # interval may be the number of seconds, or :day for day, 
    # :week for week, or :month for month. (Not Implemented Yet)
    #
    def brokerFetchInterval(symbol, 
                            interval=nil,
                            days=nil, 
                            startTime=nil, 
                            endTime=nil, eos=true, &block)
      puts "brokerFetchInterval() for %s" % symbol
      soc = dtnsoc
      if days
        soc.puts [HID, symbol, interval, days, nil, nil, nil, 1].join ','
      elsif startTime and endTime
        cmd = [HIT, symbol, interval,
               startTime.strftime(FDT), 
               endTime.strftime(FDT), 
               nil, # reserved
               nil, nil, # begin and end filter time
               1].join ','
        puts "Time %s to %s, cmd = %s" % [startTime, endTime, cmd]
        soc.puts cmd
      else # parameter problem
        raise IQFeedException.new("Parameter Error. Either days or start/end time must be given")
      end
      getResponse(soc) { |d|
        block.(d.map { |r|
                 h = Hash[r.zip(@@HIST).map { |v, (sym, func)| [sym, func.(v)]}]
                 h[:symbol] = symbol.to_sym
                 h = h.to_eos if eos
                 h
               }) 
      }
    end
  end
end # module Datafeed


# We launch the server if we are here.
# Currently, this is set up for SimpleESignalQuotes
# Also, we are doing funneling of messages.
if $SERVER_MODE
  $logger.info "IQFeed Server Starting"
  # We are a stand-alone server.
  include Datafeed

  $debug = true
  $warning = true
  $verbose = false
  $trap = false # let nothing go to the server!
  $logxml = false

  puts "DEBUG" if $debug
  puts "WARNING" if $warning
  puts "VERBOSE" if $verbose
  puts "TRAP" if  $trap
  puts "LOGXML" if $logxml

  $logger.info "Server Launching for Quotes and Historical."
  $quotes = IQFeedQuotes.new
  $historical = IQFeedHistorical.new

  $SAFE = 1
  DRb.start_service($qserverURI, $quotes)
  DRb.start_service($hserverURI, $historical, {:load_limit => 26214400 * 100})

  $logger.info "IQFeed Server is now running: quotes %s, historical %s" % [$qserverURI, $hserverURI]
  process_funnel_messages
else
  # running as client.
  DRb.start_service
end
