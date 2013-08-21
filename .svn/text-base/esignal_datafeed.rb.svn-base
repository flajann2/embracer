=begin rdoc
ESignal Datafeed

Currently, this is set up for SimpleESignalQuotes
Also, we are doing funneling of messages.

This should run on Windows with the ESignal API. Alas,
there is no indication they will port this for their latest release.
And so this will not be supported and FUCK ESignal.
=end

require 'datafeed'

module Datafeed # reopen
  # Polling switch. If enabled, we won't use events.
  POLLING = true
  POLLING_INTERVAL = 0.25 # seconds
  
  ########################################################################
  ## Simple (direct) Driver for ESignal -- basically only gets quotes
  ## in XML.
  ##
  ## This current implementation uses polling to pull regular quotes
  ## from eSignal, since we don't want to use the events interface just
  ## yet (it overworks eSignal!!!!)
  ########################################################################
  class SimpleESignalQuotes < QuoteFeed
    include DRb::DRbUndumped # Just in case -- we don't want this object pased; just references.
    include XML2Ob
    include Translate

    @@remoteURI = "druby://trader:#{PORT}" # for DRb

    @@MAPPER = {
      bid: lambda       {|k,v| [:bid, v.to_f]},
      ask: lambda       {|k,v| [:ask, v.to_f]},
      last: lambda      {|k,v| [:last, v.to_f]},
      open: lambda      {|k,v| [:open, v.to_f]},
      high: lambda      {|k,v| [:high, v.to_f]},
      low: lambda       {|k,v| [:low, v.to_f]},
      change: lambda    {|k,v| [:change, v.to_f]},
      prevClose: lambda {|k,v| [:prevClose, v.to_f]},
      volume: lambda    {|k,v| [:volume, v.to_i]},
      tradeSize: lambda {|k,v| [:tradeSize, v.to_i]},
      askSize: lambda   {|k,v| [:askSize, v.to_i]},
      bidSize: lambda   {|k,v| [:bidSize, v.to_i]},
      dateTime: lambda  {|k,v| [:dateTime, v.to_i]},
      futureExpiry: nil,
    }

    def initialize
      super
      @local_ieh = WIN32OLE.new("IEsignal.Hooks")
      
      # Here, if we are running under Windows (i.e. not remote),
      @ieh = if $SERVER_MODE
               wrap @local_ieh
             else
               @local_ieh
             end

      @app_name_given = 0
      
      # For now, we will constantly poll for symbols in the
      # postman queue.
      #
      # Sample Quote from eSignal's XMLGetBasicQuotes()
      # <Quote>
      #  <Bid>1084.5</Bid>
      #  <Ask>1084.75</Ask>
      #  <Last>1084.75</Last>
      #  <Open>1104</Open>
      #  <High>1107.75</High>
      #  <Low>1076.5</Low>
      #  <Change>-18.75</Change>
      #  <PrevClose>1103.5</PrevClose>
      #  <Volume>2033254</Volume>
      #  <TradeSize>1</TradeSize>
      #  <AskSize>538</AskSize>
      #  <BidSize>541</BidSize>
      #  <DateTime>1275658840</DateTime>
      #  <FutureExpiry></FutureExpiry>
      # </Quote>
      # 
      @thr = Thread.new {
        loop {
          sleep(0.50) 
          begin
            subtypes_of(:quote).each { |sym|
              q = translate(convert((qxml=@ieh.XMLGetBasicQuote(sym.to_s))), 
                            @@MAPPER).quote
              unless q.nil?
                transmitQuote(sym, q)
              else # remove the symbol
                remove_subtype(:quote, sym)
                puts "Faulty Symbol #{sym} removed:<#{qxml}>"
              end
            }
          rescue
            puts $!
            puts $!.backtrace.join("\n")
            # raise $!
          end
        }
      }
    end
    
    # We don't need a password for eSignal, 
    # since the application itself logs you in.
    def login(username = nil, password = nil)      
      # This object is only created under Windows.
      begin
        puts "Creating link to eSignal for #{username}"
        @ieh.SetApplication(username)
        @app_name_given += 1
      rescue
        p $!
        puts $!.backtrace.join("\n")
        @ieh = nil
        @app_name_given = false
      end if username.kind_of? String
    end

    def loggedIn?
      @app_name_given > 0
    end

    # This a not a "real" logout!!!!
    def logout
      @app_name_given -= 1
    end

    # We need to do a special create to handle DRb!!!
    def SimpleESignalQuotes.create
      if $LINUX
        puts "Creating remote Quotes Object."
        DRbObject.new_with_uri(@@remoteURI)
      else
        new #local object creation
      end
    end
  end
  
  class SimpleESignalHistorical < Historical
  end 



  ########################################################################
  ## Sophisticated Interface to ESignal
  ########################################################################
  class ESignalQuotes < QuoteFeed
  end
  
  class ESignalHistorical < Historical
  end
end # module Datafeed


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
  $serverURI = "druby://trader:#{DF_PORT_QUOTES}"
  $SAFE = 1
  DRb.start_service($serverURI, $quotes)
  puts "*** Server is now running. ***\n\n\n"
  process_funnel_messages
else
  puts "This should run under Windows with the old ESignal."
  DRb.start_service
end
