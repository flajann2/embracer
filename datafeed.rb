# DataFeed Bridge

=begin rdoc
=DataFeed Brige -- datafeeds for stock quotes and history $Rev: 1113 $

Basically, ESignal has a way to get XML quotes back, but they don't support  
the XML for everything -- yet. So, I am going to use that in a simple
driver to get those quotes.

I am no longer developing stuff for that crappy interface.
I am focusing now on IQFeed and ZenFire.

=end

# We add the curremt directory in since 1.9.2 dropped this.
$LOAD_PATH.concat %w{ ./ }

require 'fox16'
require 'xml2ob'
require 'postman'
require 'ostruct'
require 'drb/drb'
require 'logger'
require 'market'
require 'funnel'

include Funnel

# Logger for everyone to use.
$logger = Logger.new('/var/log/embracer/datafeed.log')

# We are running as a datafeed server on Windows if this is true.
$SERVER_MODE = __FILE__ == $0

# The following will fail if we are running under Linux!
begin
  require 'win32ole'
  $LINUX = false
  puts "win32ole loaded."
rescue LoadError
  $LINUX = true
  puts "datafeed remoting."
end

DF_PORT_QUOTES     = 2016
DF_PORT_HISTORICAL = 2017

module Datafeed
  include MarketFC
  
  # Our very own exceptions!
  class DatafeedException < Exception
  end

  #Symbol Lookup
  class SymbolLookup < Market
  end
  
  #Quote Base class
  class QuoteFeed < Market
    include Postman
    
    def initialize
      super
      @log_mt = :quote_log
      @gui_mt = :gui_update
      @block_hash = {} #FIX!!! This needs to be purged every so often
    end

    # get an immediate quote
    def quote(sym)
      throw new DatafeedException("Must be implemented by the vendor class.")
    end
    
    # register to listen for given list of symbols
    # syms is either a single symbol or an array of symbols to listen for.
    # 
    # The block of code gets called with (symbol, ostruct), and the ostruct
    # object will contain the particulars.
    #
    # This method returns the block passed in, so it can
    # be used to unregister later.
    def registerQuotes(syms, &block)
      raise DatafeedException("Block Needed for updates!") if block.nil?
      syms = [syms] unless syms.kind_of? Array
      syms.each { |sym| 
        register(:quote, sym.to_sym, &block) 
      }
      puts "\nregistered #{syms.join(' ')} to callback #{block}"
      @block_hash[block.hash] = block
      block.hash
    end
    
    def unregisterQuotes(syms, block_hash)
      syms = [syms] unless syms.kind_of? Array
      syms.each { |sym| unregister(:quote, :"#{sym}", &@block_hash[block_hash]) }
    end
    
    # Transmit the quote to registered listeners.
    def transmitQuote(sym, ob)
      transmit(:quote, sym.to_sym, ob)
    end
  end

  # Historical Base class
  #
  # We need to be able to grab tick and interval data. We also
  # need to be able to specify the ranges of how we grab this data.
  # 
  # Basically, this base class shall hit the local (MongoDB) database for data.
  # If the requested range (or any part thereof) is not wholly present, then
  # the base class shall hit up the subclass implementation for the additional
  # data, and cache it locally in the historical database.
  # 
  # I am thinking that we grab it from the provider, stick it in Mongo, then
  # do a normal fetch from Mongo to pull the data from there. However, that
  # can be an expensive operation and time is of the essence. So instead, we'll
  # have to do the amalgamation bit and stored newly pulled data into the database
  # in the background.
  class Historical < Market
    def getTicksByDays(symbol, days, eos=true, &block)
      fetchTicks(symbol, days, nil, nil, eos, &block)
    end

    def getTicksOverTime(symbol, startTime, endTime, eos=true, &block)
      fetchTicks(symbol, nil, startTime, endTime, eos, &block)
    end

    def getIntervalByDays(symbol, interval=60, days=10, eos=true, &block)
      fetchInterval(symbol, interval, days, nil, nil, eos, &block)
    end

    def getIntervalOverTime(symbol, interval, startTime, endTime, eos=true, &block)
      fetchInterval(symbol, interval, nil, startTime, endTime, eos, &block)
    end

    def getDaysByDays(symbol, days=120, eos=true, &block)
      fetchInterval(symbol, :day, days, nil, nil, eos, &block)
    end

    def getDaysOverTime(symbol, startTime, endTime, eos=true, &block)
      fetchInterval(symbol, :day, nil, startTime, endTime, eos, &block)
    end

    def getWeeksByWeeks(symbol, weeks=52, eos=true, &block)
      fetchInterval(symbol, :week, weeks * 7, nil, nil, eos, &block)
    end

    def getWeeksOverTime(symbol, startTime, endTime, eos=true, &block)
      fetchInterval(symbol, :week, nil, startTime, endTime, eos, &block)
    end

    def getMonthsByMonths(symbol, months=24, eos=true, &block)
      fetchInterval(symbol, :month, momths * 31, nil, nil, eos, &block)
    end

    def getMonthsOverTime(symbol, startTime, endTime, eos=true, &block)
      fetchInterval(symbol, :month, nil, startTime, endTime, eos, &block)
    end

    # Generalized tick fetch.
    #
    # If the block is used, the arrays will be retured in chunks, which should be
    # accumulated. This is to eliminate the problem of passing large arrays across 
    # DRb.
    def fetchTicks(symbol, days=nil, startTime=nil, endTime=nil, eos=true, &block)
      brokerFetchTicks(symbol, days, startTime, endTime, eos, &block)
    end

    # Generalized interval  fetch
    #
    # interval may be the number of seconds, or :day for day, 
    # :week for week, or :month for month.
    #
    def fetchInterval(symbol, interval, days=nil, startTime=nil, endTime=nil, eos=true, &block)
       brokerFetchInterval(symbol, interval, days, startTime, endTime, eos, &block)
    end
  end
  class IQFeedQuotes < QuoteFeed
  end

  class IQFeedHistorical < Historical
  end

end # Module Datafeed

# special cases (we should elminate having to pull this in here. Well, small moves. FIX!!!)
#require 'esignal_datafeed'
#require 'iqfeed_datafeed'

# We launch the server if we are here.
# Currently, this is set up for SimpleESignalQuotes
# Also, we are doing funneling of messages.
if $SERVER_MODE and not $LINUX
  # We are a server.
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

  puts "Server Launching for Quotes and Historical."
  puts "NOTE WELL: Historical is not available yet!!!"
  $quotes = SimpleESignalQuotes.new
  $serverURI = "druby://trader:#{PORT}"
  $SAFE = 1
  DRb.start_service($serverURI, $quotes)
  puts "*** Server is now running. ***\n\n\n"
  process_funnel_messages
else
  # We are a clent. And there will be callbacks.
  DRb.start_service
end
