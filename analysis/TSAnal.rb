# TSAnal = $Rev$

require 'mongo'
require 'thread'

=begin rdoc
= TSAnal -- base clases for Time Series Analysis

We need a good framework for which to launch Time Series Analysis
modules. This is meant to be more in batch mode than in real time,
though we may make provisions for that shortly.

We shall store results of these runs in collections that are keyed
to the tick data that they represent. The identifying compound key
shall be the tick's _id, symbol, timestamp

=end
module TSAnal

  class BobbinException < Exception
  end

  #= Bobbin -- base class to derive all Bobbin type clases
  #
  # A Bobbin in this context is an object that will be given
  # a steady stream of data to analyze, where it will do what it needs
  # internally to store and process, etc what it must to compute
  # specifics in for that data.
  #
  # The data is read by one thread and is put in a queue. The neeed
  class Bobbin 
    # so these can be read by the spool_initiator!
    attr_reader :symbol, :startDT, :endDT

    # Place to push and pop the data
    attr :data, true

    def initialize(symbol, startDT = nil, endDT = nil)
      @symbol = symbol
      @startDT = startDT.to_time
      @endDT = endDT.to_time
      @data = Queue.new # data queue
      @done = false
    end

    # Call this to start the analyasis.
    def run()
      # spooling
      @spoolT = Thread.new do
        spool { |datum|
          @data << datum
        }
        @done = true
      end
      
      # needling
      @needleT = Thread.new do
        while not @done
          needle @data.shift
        end        
      end
      @needleT.join
      @spoolT.join
    end

    # Iterator for new data (must be implemented by subclass with a yield)
    def spool
      throw BobbinException.new "Must be impletmented by subclass (with yield)"
    end

    # This will call the handler with each object singly from the queue to be handled.
    def needle(datum)
      throw BobbinException.new "Must be impletmented by subclass (with yield)"
    end
  end

end

# Testing
if __FILE__ == $0
  require 'logger'
  $logger = Logger.new('/var/log/embracer/TSAnal.log')
  $logger.level = Logger::DEBUG
  $debug = true
  $warning = true
  $verbose = true
  $trap = false # let nothing go to the server!
  $logxml = true

  puts "TSAnal Testing"
  puts "DEBUG" if $debug
  puts "WARNING" if $warning
  puts "VERBOSE" if $verbose
  puts "TRAP" if  $trap
  puts "LOGXML" if $logxml


end
