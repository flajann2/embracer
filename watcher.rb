=begin rdoc
=The Watcher -- classes to watch the progression of a trade, to manage getting into a trade, etc.

The Watcher comprises a number of modules all derived from the Watcher base class. It shall
run as a thread and issue orders to the broker, accept input from quotes and historical, etc.,
and  interact with the GUI Front-end.

The Watcher shall abstract the details of market entry and exit -- all I need to deal with
is the right Watcher for the job. 

This will allow us tremendous flexibility in how The Watchers operate.

=Commands
See WatcherFramework::Watcher for a list of commands that can be given to the Watchers
in general.

The subclass shall have do_cmdXXX methods defiened to handle the cmdXXX commands.

=States and MicroStates

The subclass shall have do_xxxxx(m) methods defined for each xxxxx state.
The 'm' parameter is a microstate that the state handlers may use as a persistent
local state objects to hold all of its necessary variables.

Upon new invocations of the state handlers, the m ostruct shall be created afresh, marking
the beginning of invocations.

=end

require 'ostruct'
require 'postman'
require 'funnel'
require 'broker'
require 'bells'

=begin rdoc
=The Watcher Framework -- a module of basic Watcher Functionality

Here, all base classes and base functionality common to all Watchers
are defined here.

=end
module WatcherFramework
  class WatcherException < MarketException
  end

  #= State machine for Watchers
  # A legal state must be listed here, on an exception will incur.
  STATES = {
    :dead => "Dead", # pre-state, before thread has been activated.
    :dormant => "Waiting for activation",
    :seeking_entry => "Seeking Entry", # Looking for the 'best' entry point into the market.
    :pending_entry => "Pending entry", # waiting for a trade to be executed
    :hot => "In a trade!", # in a trade, active watching mode
    :failed => "DANGER:: FAILURE", # SERIOUS -- a broker operation failed!!!!!
    :pending_flat => "Exiting trade...", # waiting for confirmation of an exit
    :pending_half_flat => "Exiting half of trade...", # waiting for confimation of a half-flat.
    :pending_reversal => "Waiting to reverse trade...", # Trade reveral!!!!
    :reversal => "Reversing Trade!",
    :pending_panic => "Attemoting to kill all outstanding orders...",
    :panic => "All orders sucessfully killed",
    :flat => "Flat!", # confirmation of a trade succefully executed.
    :bug => "Software Bug Detected", # SPECIAL CASE -- bug detected in software. BAD BAD BAD!
  }

  #= Map of allowable State Transistions
  # A legal transistion must be listed here, or an exception will be generated.
  TRANSITIONS = {
    :dead              => [:dormant],
    :dormant           => [:seeking_entry],
    :seeking_entry     => [:seeking_entry, :pending_entry, :pending_panic, :failed],
    :pending_entry     => [:hot, :pending_panic, :failed],
    :hot               => [:pending_flat, :pending_half_flat, :pending_reversal, :failed],
    :pending_flat      => [:flat, :failed],
    :pending_half_flat => [:hot, :failed],
    :pending_reversal  => [:reversal, :failed],
    :reversal          => [:hot, :failed],
    :pending_panic     => [:panic, :pending_entry, :failed],
    :panic             => [:dormant, :failed],
    :flat              => [:dormant, :failed], # now can be used for a new trade.
    :failed            => nil, # this is a serious condition requiring human intervention
  }

  # Default sleep quantum.
  DEFAULT_SLEEP_QUANTUM = 0.10

  #=Postman Messages
  # We list these here mainly for documentation reasons.
  POSTMAN_MESSAGES = [
                      # All state transistions
                      [:state, :transistion],
                      # Geneal Notifications 
                      [:status, :update],
                      # Profit/Loss updates (when in a live trade)
                      [:profit, :update],
                     ]

  #= The Watcher -- Base class for all Watchers
  # The Watcher classes all run their own threads to manage the trades they have
  # been invoked for.
  #
  # The Watcher uses a State Machine to drive the progress of trades. Also, The Watcher
  # broadcasts messages to listeners through the Postman mixin.
  #
  # The Read-Only attributes of this class (except where otherwise noted)
  # is meant more for documentation and is not really geared to be read. 
  # Use Postman to get that information!!!!
  #
  # Each microstate has a sleep_quantum property which is always set to
  # a default of 0.10 second upon each invocation. The state handler may
  # set this to a different value, but it must be done as needed upon
  # each invocation.
  class Watcher
    include Postman
    include Bells

    @@all_watchers = []

    # *Armed* for *REAL* *TRADING*?
    # it is if this is true!!!!
    attr_accessor :armed
    alias_method :armed?, :armed

    # State of the machine.
    attr_reader :state 
    
    # Name of the Watcher.
    attr_reader :name

    # Description of the watcher.
    attr_reader :desc

    # Trade Profit/Loss (calculated by the subclass)
    attr_reader :tradePL
    # (really internal!!!) prior calculation of trade P/L
    attr_reader :last_tradePL

    # Total P/L for the session. Does not include current trade.
    attr_reader :totalPL
    
    # Srike price/point of a trade
    attr_reader :strike

    # Time of strike.
    attr_reader :strikeTime

    # Instantaneous Quote.
    attr_reader :quote

    # If this is true, then create fresh microstates upon
    # each invocation. Else, only do so upon going dormant.
    attr_reader :fresh_microstates

    # Future symbol for the DataFeed (Quotes)
    attr_reader :future
    # Future symbol for the broker (MUST REFER TO THE SAME INSTRUMENT AS @future)
    attr_reader :future_broker
    # Number of contracts to buy (negative value for shorting)
    attr_reader :contracts

    # (Calculated) Tick Quantum (tick size)
    attr_reader :tickq
    # (Calculated) Value per Tick Quantum (per point == tickv / tickq)
    attr_reader :tickv

    # Commissions to be paid per contract per transaction (not including fees)
    attr_reader :commissions

    # (calculated/gotten from Broker) Broker Fees excluding commissions
    attr_reader :brokerFee
    # (really internal!!!) last time calculation of P/L was performed *and* transmitted.
    attr_reader :lastCalcTime

    # Additional Fields (parameters) the Watcher needs 
    # (should be exposed on the user interface for entry)
    #
    # You may use this directly, since this is static information.
    #
    ## format:
    ### [[:symName, (:bool|:int|:float|:string), 
    ###    default_value, "display name", "description"],...]
    attr_reader :fields 
    
    # Calculated limit on an entry.
    attr_reader:limitEntry

    # Caclulated stop out for the current position (shall be updated 
    # as trade progresses.
    attr_reader :stopOut
    
    # Returns [:state, "description"]
    def state_info
      [@state, STATES[@state]]
    end
    
    # Must be called by the subclases before anything else is done.
    # Also, @thread must be set up with the Watcher thread, as it will be
    # awakened here by any command function.
    def initialize
      super
      @@all_watchers << self

      @armed = false
      @fresh_microstates = false

      @cmd_queue = []
      @thread = nil
      @state = :dead
      @microstates = {} # persistent microstate objects (OpenStructs)
      @profitPL = @totalPL = @balance = @tradePL = 0
      @quote = @strike = @strikeTime = nil
      @lastCalcTime = Time.now
    end

    # overrides must call the base class
    def shutdown
      @cmd_queue << [:shutdown]
      @@all_watchers -= [self]
      @thread.wakeup if @thread.stop?
    end

    def cmdBuy(future, future_broker, contracts, *fields)
      @cmd_queue << [:cmdBuy, future, future_broker, contracts, fields]
      @thread.wakeup if @thread.stop?
    end

    def cmdSellShort(future, future_broker, contracts, *fields)
      @cmd_queue << [:cmdSellShort, future, future_broker, contracts, fields]
      @thread.wakeup if @thread.stop?
    end

    def cmdGoFlat
      @cmd_queue << [:cmdGoFlat]
      @thread.wakeup if @thread.stop?
    end

    def cmdReverse
      @cmd_queue << [:cmdReverse]
      @thread.wakeup if @thread.stop?
    end

    def cmdGoHalfFlat
      @cmd_queue << [:cmdGoHalfFlat]
      @thread.wakeup if @thread.stop?
    end

    # Kill all orders (or attempt to before they are filled)
    def cmdPanic
      @cmd_queue << [:cmdPanic]
      @thread.wakeup if @thread.stop?
    end


    # Cause Watcher to flash something about its current state to the listeners.
    def ping
      @cmd_queue << [:ping]
    end

    def do_ping
      transmit(:state, :transition, @state)      
    end

    #= Transistion state (and check for legality of transistion)
    #
    # Note that a microstate instance object is created upon the transistion
    # and is passed to the state handler upon each check.
    #
    # That microstate instance is created afresh on each new state transistion.
    # if something needs to persist across state transistions, consider storing
    # that object in the instance, not the microstate instance.
    #
    # Be aware, of course, that you don't want to polute the instance space with a 
    # lot of microstates.
    def state_to(state, *rest)
      _state_to(state, false, *rest)
    end

    #= Frsesh Transistion
    # Like state_to, but ensures the microstate object is
    # fresh before the transistion.
    def fresh_state_to(state, *rest)
      _state_to(state, true, *rest)
    end

    def _state_to(state, clear_microstate, *rest)
      # Firstly, check the legality of this state transistion
      raise WatcherException.new("Illegal State Transition(#{@state} -> #{state})") unless state != :bug and TRANSITIONS[@state].member? state
      @state = state
      @microstates = {} if state == :dormant
      @microstates[state] = OpenStruct.new if @fresh_microstates or @microstates[state].nil? or clear_microstate
      transmit(:state, :transition, state, @contracts, *rest)
    end

    # GUI Configuration of the Watcher. Must be implemented by the subclass!!!
    def doGUIConfig
      raise WatcherException.new "Not Implemente Yet -- Must be implemented by subclass!"
    end

    # The heart of the matter -- the State Machine that drives everything.
    #
    # The microstate is set initially with a sleep_quantum of 0.10, but
    # this may be changed by the state handler itself. It will have to do
    # a change on each and every invocation else the default will go back
    # to 0.10 second.
    def run_state_machine
      loop {
        cmd = @cmd_queue.shift
        begin
          unless cmd.nil?
            c = cmd.shift
            transmitStatusUpdate("#{c} command received.")
            send(:"do_#{c}", *cmd)
            bell_click
          else # state checking
            unless [:failed, :bug].member? @state
              # Here we will set the sleep quantum always to be 0.10,
              # but the state handler itself may reset this. And will
              # have to on every invocation!
              #
              # Note that because we can have @state transistioned within a state handler,
              # we must keep track of what state the sleep_quantum was set for, hince
              # qstate.
              @microstates[qstate = @state].sleep_quantum = DEFAULT_SLEEP_QUANTUM
              send(:"do_#{@state}", @microstates[@state])
              sleep(unless @microstates[qstate].nil?
                      @microstates[qstate].sleep_quantum
                    else
                      DEFAULT_SLEEP_QUANTUM
                    end) # Will be awakened early if need be.
            else
              Thread.stop
            end
          end
        rescue Exception => err
          p err
          puts err.backtrace.join("\n")
          state_to :bug, err, c, cmd
        end
      }
    end
  end
end


=begin rdoc
=The Grunts Mixin

This module contains most or all of the "grunt" routines that will
do the grungy bits of pulling useful information from the Broker and
Quote objects.

To accquire the singleton broker, quote, and historical objects, do the following:
- App.EM.broker
- App.EM.quotes
- App.EM.historical
=end
module Grunts
  require 'application'
  include Application
  include Orders
  include Bells

  # Order Status for an open order.
  OS_OPEN = "Open"
  # Order Status for a cancelled order.
  OS_CANCELLED = "Cancelled"
  # Order Status for a filled order.
  OS_FILLED = "Filled"

  # Get the Futures information.
  #
  ## Return [sym, description, tickq, tickv, fee]
  ## Note that "fee" is a sum of different fees, and does not include commission.
  def getFuturesInfo(sym)
    f = App.EM.broker.getFuturesData(sym)
    raise WatcherException("getFuturesInfo(#{sym}) Error: #{f.ErrorMsg}") unless f.ErrorMsg.nil?
    [
     f.symbol,
     f.productDescription, 
     f.tickSize.to_f, 
     f.tickSize.to_f * f.contractSize.to_f,
     f.exchangeFee.to_f + f.nFAFee.to_f + f.exchFee.to_f
    ]
  end

  # Start a quote feed, and put the results in the @quote instance variable.
  # We'll also store the handle in @qfeedhandle
  def startQuoteFeed
    endQuoteFeed unless not defined? @qfeedhandle or @qfeedhandle.nil?
    @qfeedquote = @future
    @qflambda = lambda { |q| @quote = q }
    @qfeedhandle = App.EM.quotes.registerQuotes(@future, &@qflambda)
  end

  # Swutch off quote feed
  def endQuoteFeed
    App.EM.quotes.unregisterQuotes(@qfeedquote, @qfeedhandle) unless @qfeedhandle.nil?
    @qfeedhandle = @qfeedquote = nil
  end

  # Set the fields given in a field list automatically.
  def set_fields(*f)
    f.each{ |sym, val| instance_variable_set(:"@#{sym}", val) }
  end

  # Get Position Status and filter out those that match
  # the given optional parameter.
  #
  ## sym is the @future_broker symbol, if given.
  def getOutstandingPositions(sym = nil)
    apos = App.EM.broker.getPositions()
    apos.delete_if { |pos| pos.symbol != sym } unless sym.nil?
    apos
  end

  # Get the Order Status and possibly filter them on Symbol and Order Type
  # 
  ## sym is the @future_broker symbol, if given.
  ## otype may be OS_OPEN, OS_CANCELLED, or OS_FILLED.

  def getOutstandingOrders(sym = nil, otype = nil, orderID = nil)
    aos = App.EM.broker.getOrderStatus
    aos.delete_if {|os| os.symbol != sym} unless sym.nil?
    aos.delete_if {|os| os.orderStatus != otype} unless otype.nil?
    aos.delete_if {|os| os.orderID != orderID} unless orderID.nil?
    aos
  end

  # (internal) returns [action, orderType]
  def action_orderType(ee, contracts, limit, stop)
    [ if contracts > 0
        case ee
        when :entry
          OA_BUY
        when :exit, :reversal
          OA_COVER_SHORT
        end

      elsif contracts < 0
        case ee
        when :entry
          OA_SHORT
        when :exit, :reversal
          OA_SELL
        end
      else
        raise MarketException.new("Contract size must not be zero.")
      end,
      
      if limit > 0 and stop == 0
        OT_LIMIT
      elsif stop > 0 and limit == 0
        OT_STOP
      elsif stop == 0 and limit == 0
        OT_MARKET
      else
        raise MarketException.new("Invalid limit/stop parameters")
      end ]
  end
  private :action_orderType

  PLACE_ORDER_DIRECTIONS = [:entry, :exit, :reversal]
  
  # Place the order with the broker. 
  #
  # Negative contracts denote a short rather than a long.
  #
  # Returns the orderID (not wrapped in an oStruct), or
  # throws an exception if the order did not take for some
  # reason.
  #
  # Obviously, the symbol must be the @future_broker symbol.
  # Or symbology that the broker recognizes.
  #
  # Do NOT supply both a limit and a stop value -- only give
  # one or the other. If neither are given, that's taken as a 
  # MARKET order.
  #
  # ee is either :entry, :exit, or :reversal -- used to determine if it should
  # either do BUY/SHRT or SELL/BTOC on entry and exit orders, respectively.
  # Also, will automatically reverse the sign of @contracts as well as handle
  # properly the reversal situation for you.

  def placeBrokerOrder(ee, sym, contracts, limit = 0, stop = 0)
    raise MarketException.new("Direction Parameter Error #{ee}: must be either #{PLACE_ORDER_DIRECTIONS}") unless PLACE_ORDER_DIRECTIONS.member? ee
    contracts = -contracts if ee == :exit
    contracts = -2 * contracts if ee == :reversal

    action, orderType = action_orderType(ee, contracts, limit, stop)
    osr = App.EM.broker.placeOrder(order(sym, action, contracts.abs, orderType, limit, stop))
    # at this point, the orderID is either > 0 (order placed), or 0 (error, with error as 
    # the message.)
    raise MarketException.new("Order was not placed: #{osr.error}") unless osr.error.nil?

    # Log this order in the database. NOTE that contracts will have its sign flipped dependent on what ee is.
    App.DB["orders"].insert({ type: :placeBrokerOrder,
                              ee: ee,
                              sym: sym, 
                              contracts: contracts, 
                              limit: limit, 
                              stop: stop, 
                              orderID: osr.orderID,
                              time: Time.now,
                            })
    return osr.orderID    
  end

  # Modify an existing broker order.
  #
  # Returns the new orderID, which should be now used in place of the old one.

  def modifyBrokerOrder(ee, orderID, sym, contracts, limit = 0, stop = 0)
    raise MarketException.new("Direction Parameter Error #{ee}: must be either #{PLACE_ORDER_DIRECTIONS}") unless PLACE_ORDER_DIRECTIONS.member? ee
    contracts = -contracts if ee == :exit

    action, orderType = action_orderType(ee, contracts, limit, stop)
    osr = App.EM.broker.modifyOrder(orderID, order(sym, 
                                                   action, 
                                                   contracts.abs, 
                                                   orderType, 
                                                   limit, stop))
    # at this point, the orderID is either > 0 (order placed), or 0 (error, with error as 
    # the message.)
    raise MarketException.new("Order was not modified: #{osr.error}") unless osr.error.nil?

    # Log this order. note that contracts will have its sign flipped depending on ee.
    App.DB[:orders].insert({ type: :modifyBrokerOrder,
                             ee: ee,
                             sym: sym, 
                             contracts: contracts, 
                             limit: limit, 
                             stop: stop,
                             oldOrderID: orderID,
                             orderID: osr.orderID,
                             time: Time.now,
                           })

    return osr.orderID    
  end

  # Cancel an order.
  def cancelBrokerOrder(orderID)
    o = App.EM.broker.cancelOrder(orderID)
    raise MarketException.new("Cancellation failed: #{o.error}") unless o.error.nil?
    App.DB[:orders].insert({ type: :cancelBrokerOrder,
                             orderID: orderID,
                             time: Time.now,
                           })
    o.orderID
  end

  # Timestamp string YYYY-MM-DD HH:MM:SS
  def now
    Time.now.strftime("%F %H:%M:%S")
  end

  # Send status updates to the listeners.
  ## Message Type
  ### :status
  ## Message Subtype
  ### :update
  def transmitStatusUpdate(m)
    
    transmit(:status, :update, "#{now} >>#{m}")
  end

  # Send profit/loss updates.
  ## Message Type
  ### :profit
  ## Message Subtype
  ### :update
  def transmitProfitLossUpdate(pointPL, tradePL, totalPL, balance, timeInTrade = nil)
    transmit(:profit, :update, pointPL, tradePL, totalPL, balance, timeInTrade)
  end

  # Set Strike Quote and Time
  def setStrike(point = nil)
    @strike = unless point.nil?
                point
              else
                @quote.last
              end
    @strikeTime = Time.new
  end
  
  # Calculate the instantaneous profit/loss, etc.
  # If there was a change since last calculation, transmit the results.
  def calculateProfitLoss(finalize = false, exitPoint = nil)
    currentTime = Time.now
    pointPrice = @tickv / @tickq
    xpoint = unless exitPoint.nil?
               exitPoint
             else
               @quote.last
             end
    pointPL = xpoint - @strike
    cost = 2 * (@commissions + @brokerFee) * @contracts.abs
    @tradePL = pointPrice * @contracts * pointPL - cost
    if finalize or not defined? @last_tradePL \
      or @tradePL != @last_tradePL \
      or currentTime - @lastCalcTime >= 1
      dst = if @strikeTime.dst?
              3600
            else
              0
            end
      timeInTrade = Time.at(currentTime - @strikeTime \
                            - @strikeTime.gmtoff + dst).strftime("%H:%M:%S")

      if finalize
        @totalPL += @tradePL
        @balance += @tradePL
      end

      transmitProfitLossUpdate(pointPL * lsfactor, @tradePL, @totalPL, @balance, timeInTrade)

      unless finalize
        @last_tradePL = @tradePL
        @lastCalcTime = currentTime
      else
        @last_tradePL = nil
        @lastCalcTime = nil
      end
    end
  end  

  # True if this is a long trade.
  # NOTE: Always ask for the trade you are expecting.
  def long?
    @contracts > 0
  end

  # True if this is a short trade.
  # NOTE: Always ask for the trade you are expecting.
  def short?
    @contracts < 0
  end

  # Long-Short Factor -- 1 for long, -1 for short.
  def lsfactor
    if long?
      1
    elsif short?
      -1
    else
      0 # Should never get this -- this would happen on a zero contract size.
    end
  end
end


=begin rdoc
=The Follower -- basic trade maintenance

The Follower shall maintain a trade basically by doing something like a trailing stop,
but smarter.

The Follower will typically look to stop out at half the distance from strike initally, 
but tighten that stop as the trade progresses.

=end
module Follower
  include WatcherFramework
  include Orders

  MAX_POS_CHECK_COUNT = 50 # 5 seconds

  class Follower < Watcher
    include Grunts
    include Orders

    # Watcher input fields to get from user.
    @@FIELDS = [
                [:limit_off,  :float, 0.25,  "Limit Offset","Limit Offset from current"],
                [:market_ord, :bool,  FALSE, "Market",      "Market Order(immediate entry)"],
                [:stop_off,   :float, 2.00,  "Stop Offset", "Initial Stopout Offset from current"],
                [:stop_off_even, :float, 2.00, "Upg to Even",
                 "Upgrade Stopout to even when point profit goes above this."],
                [:hour_sigmoid, :float, 2.0,  "Hour Sigmoid", "25-75% Sigmoid Interval in Hours"],
                [:commissions,:float, 6.99,"Commissions", "Price per contract(not including fees"],
               ]
    
    # Later, we'll specify Watcher-based fields to notify of internal changes.
    # For now, this is not used. FIX!!!!
    @@DISPLAY = [] 

    # Order ID for entry.
    attr_reader :orderIDEntry
    # Order ID for exiting a position.
    attr_reader :orderIDExit
    # Order ID for the (currently active) stop out
    attr_reader :orderIDstop
    # Position ID for the currently active position
    attr_reader :positionID
    
    # This is filled in when a stop order was hit and needs to be 
    # passed from :hot to :pending_flat. Otherwise, this is nil.
    attr_reader :stopOrder

    def initialize
      super
      @name = "Follower"
      @desc = "'Simple' Movement Follower"
      @fields = @@FIELDS

      @orderIDEntry =  @orderIDExit =  @orderIDStop = @positionID = nil
      @stopOrder = nil

      @thread = Thread.new { run() }
    end
    
    # The Follower Thread.
    def run
      begin
        state_to :dormant, "The #{@name} Lives!"
        run_state_machine
      rescue
        p $!
        puts $!.backtrace.join("\n")
      end
    end

    # Short Message about whether or not we are armed.
    def armt
      if armed?
        "<ARMED>"
      else
        "(paper)"
      end
    end

    # Short message about whether or not we are long or short.
    def lors
      if long?
        "LONG"
      elsif short?
        "SHORT"
      else
        "<<ERR>>"
      end
    end

    # Short message as to whether this is a LIMIT or MARKET order.
    def lorm
      if @market_ord
        "MARKET"
      else
        "LIMIT"
      end
    end

    def do_cmdBuy(future, future_broker, contracts, fields)
      @future = future
      @future_broker = future_broker
      @contracts = contracts
      set_fields(*fields)
      state_to :seeking_entry, %{BUY #{contracts} #{future} / (#{future_broker}) contract(s), limit offset #{@limit_off}, market order? #{@market_ord}, stop offset #{@stop_off}, commissions $#{@commissions}}
    end

    def do_cmdSellShort(future, future_broker, contracts, fields)
      @future = future
      @future_broker = future_broker
      @contracts = -contracts
      set_fields(*fields)
      state_to :seeking_entry, %{SHORT #{contracts} #{future} (#{future_broker}) contract(s), limit offset #{@limit_off}, market order? #{@market_ord}, stop offset #{@stop_off}, commissions $#{@commissions}}
    end

    def do_cmdGoFlat
      state_to :pending_flat, "#{armt} Flatten your position."
    end

    def do_cmdReverse
      state_to :pending_reversal, "#{armt} Reverse your position"
    end

    def do_cmdGoHalfFlat
      state_to :pending_half_flat, "#{armt} Dumping half your position."
    end

    def do_cmdPanic
      state_to :pending_panic, "#{armt} Attempting to Cancel all Outstanding Orders!!!"
    end

    # Dormant state -- we really don't do much with this state,
    # live or not.
    def do_dormant(m)
      # Just because I'm paranoid.
      @stopOrder = nil
    end

    # State of Seeking Entry.
    #
    # Here we are simply looking to find a good entry point into the market.
    # in the follower's case, we are simply going to enter immediately and therefore
    # do an immediate shift into pending_entry.
    #
    ## 1) Pull information on the Future, and calculate tickq and tickv, 
    ##    fees, and the like.
    ##
    ## 2) Check for any outstanding orders or positions.
    ##
    ## 3) If nothing is there, then
    ### 3a) transistion to :pending_entry
    def do_seeking_entry(m)
      begin
        m.sym, m.desc, @tickq, @tickv, @brokerFee = getFuturesInfo(@future_broker) unless m.sFI
        m.sFI = true

        startQuoteFeed unless m.sQF
        m.sQF = true
        
        # Here, we want to check to see if we have any prior outstanding
        # orders, and if so, we wish to abort entry.
        unless armed? \
          and (not (ost = getOutstandingOrders(@future_broker, OS_OPEN)).empty?) \
          and (not (ost = getOutstandingPositions(@future_broker)).empty?)
          state_to :pending_entry, "#{armt} Acquiring #{@contracts} of #{m.sym}, fee #{@brokerFee}"
        else
          # We cannot proceed. Bail
          state_to :failed, "Fail to enter new position because of outstandings: #{ost}"
        end
      rescue MarketException
        p $!
        puts $!.backtrace.join("\n")
        state_to :failed, $!
      end
    end


    # State of pending entry.
    #
    # The state that led to this one has already done some of the homework
    # for us. In particular, we know we have no outstanding positions at this
    # point, and also no outstanding orders.
    #
    # Here are the steps we need to take in order to accquire the future:
    ## 1) calculate entry point and stopout values
    ## 2) If armed, enter the order to acquire the issue (Use OTO)
    ## 3) upon verification that the order has been acquired,
    ##    transition to :hot
    #
    # We employ a micro-state machine to manage all of this.
    #
    # NOTE WELL that we can't really do an OTO due to lack of documentation on the
    # sActiveOrderType field, so we shall break it up into two seperate trades.
    #
    # This means, of course, that we will have to sit around waiting for the
    # first order to fill before we issue the 2nd (stop) order. Very annoying,
    # but we have no choice in the matter.
    def do_pending_entry(m)      
      go_hot = lambda {
        state_to :hot, "#{armt} Going hot on a #{lors} stike at #{@strike} with a stopuout of #{@stopOut}."
      }
      begin
        case m.state # microstate
        when nil # first time thru
          @orderIDEntry = @orderIDStop = nil # just to be sure.
          m.quote = @quote # so this does not change from under us.
          m.point = m.quote.last # this will obviously be updated in an ARMED case.

          if m.quote.bid == 0 or m.quote.ask == 0 or m.quote.last == 0
            raise MarketException.new("Bad Quotes from Datafeed -- Market probably not trading now.")
          end

          @limitEntry = if long?
                          m.quote.bid - @limit_off
                        else
                          m.quote.ask + @limit_off
                        end

          @stopOut = if long?
                       m.point - @stop_off
                     elsif short?
                       m.point + @stop_off
                     else
                       raise MarketException.new("You can't have zero contracts, silly!")
                     end

          if armed?
            # We enter the naked LIMIT/MARKET order here, we'll cover it in the next microstate
            @orderIDEntry = placeBrokerOrder(:entry, @future_broker, @contracts, 
                                             unless @market_ord
                                               @limitEntry
                                             else
                                               0 # Market order if this is zero.
                                             end)
          end
          transmitStatusUpdate "#{armt} Waiting for #{lors} #{lorm} entry of #{@limitEntry} [##{@orderIDEntry}]"
          m.state = :check_entry_order

        when :check_entry_order
          if armed?
            # Check that entry order is FILLED
            # Do the stop order when confirmed.
            os = getOutstandingOrders(nil, nil, @orderIDEntry)[0]

            #(in)Sanity Checks!!!!
            raise MarketException.new("Can't find our order #{@orderIDEntry} !!!!?!") if os.nil?
            raise MarketException.new("Order Numbers Mismatch: #{@orderIDEntry} != #{os.orderID}") unless @orderIDEntry == os.orderID

            # Now we check the order status itself. It should either be OSS_OPEN or OSS_FILLED.
            case os.orderStatus
            when OSS_OPEN
              # Not filled yet. Do nothing.
              
            when OSS_FILLED
              # Order was filled. Yay!!!!
              # Now (QUICKLY!) place in the stop order.
              m.strike = os.execPrice
              @orderIDStop = placeBrokerOrder(:exit, @future_broker, @contracts, 0, @stopOut)
              bell_filled
              transmitStatusUpdate "#{armt} Order is now filled. Placing Stop at #{@stopOut} "
              m.state = :check_stop_order

            when OSS_CANCELLED
              # Something cancelled this order externally(?)
              state_to :failed, "Unexpected cancellation of order##{@orderIDEntry}"

            else
              raise MarketException.new("Wierd OrderStatus: #{os.orderStatus}")
            end
          else
            transmitStatusUpdate "#{armt} "
            m.posCheckCount = 0
            m.state = :check_stop_order
          end

        when :check_stop_order
          if armed?
            # Checking our stop order!!!

            os = getOutstandingOrders(nil, nil, @orderIDStop)[0]
            #More (in)Sanity Checks!!!!
            raise MarketException.new("Can't find our order!!!!?!") if os.nil?
            raise MarketException.new("Order Numbers Mismatch: #{@orderIDStop} != #{os.orderID}") unless @orderIDStop == os.orderID

            # This is simple -- the stop order should be in the OSS_OPEN state.
            case os.orderStatus
            when OSS_OPEN
              # All is well with the world. Now pull position and get the REAL strike price!
              @position = po = getOutstandingPositions(@future_broker)[0]
              
              # Even more(in)Sanity Checks!!!!!!
              unless po.nil?
                transmitStatusUpdate("#{armt} We were filled on #{po.symbol} at #{po.strikePrice}")
                setStrike m.strike # m.strike set in :check_entry_order->OSS_FILLED microstate!
                go_hot.()
              else # either the position status has not been updated yet, or there is another problem
                m.posCheckCount += 1
                raise MarketException.new("WTF? Can't get the POSITION Information!!!!") unless m.posCheckCount < MAX_POS_CHECK_COUNT 
              end

            else # Somethins is fishy.
              raise MarketException.new("#{armt} Stop Order Status is unexpectly #{os.orderStatus}")
            end
            
          else # paper trading
            if @market_ord  or ((@limitEntry - @quote.last) * lsfactor >= 0)
              setStrike(unless @market_ord
                          @limitEntry
                        else
                          nil
                        end)
              go_hot.()
            end
          end

        else # Unknown microstate
          raise MarketException.new("Unknown Microstate #{m.state}")
        end
          
      rescue MarketException
        p $!
        puts $!.backtrace.join("\n")
        state_to :failed, $!
      end unless @quote.nil? # we need quote information before we may proceed.      
    end
    
    #= Sigmoid Trade following -- start of percentage of move.
    # We have decided that this should be at 0% (breaking even), and
    # it will go up from there.
    SIGMOID_BOT = 0.00

    #= Sigmoid Trade following -- end of the trade.
    # We may have to adjust this, and perhaps we should
    # allow this bit to be adjusted by the user. Though, I lean against
    # that.
    SIGMOID_TOP = 0.75

    # We are now in a position. Monitor and manage.
    def do_hot(m)
      m.point = @tickv / @tickq if m.point.nil?
      m.counter = 0 if m.counter.nil?
      begin
        calculateProfitLoss
        case m.state
        when nil # initialization
          bell_entered_position
          m.upEven = false # even upgrade
          m.dpoint = m.dpointPeak = m.dstop = m.dstopPeak = 0
          m.sig = SIGMOID_BOT
          m.state = :checking

        when :checking
          m.dpoint = (@quote.last - @strike) * lsfactor
          m.dpointPeak = [m.dpoint, m.dpointPeak].max
          m.dstop = (@quote.last - @stopOut) * lsfactor
          m.dstopPeak = [m.dstop, m.dstopPeak].max
          m.sleep_quantum = 5.0 # we throttle back to checking every 5 seconds here.

          if armed?
            # Check order status and whether or not it sold off.
            os = getOutstandingOrders(nil, nil, @orderIDStop)[0]
            case os.orderStatus
            when OSS_OPEN
              # Do Nothing
            when OSS_FILLED
              @stopOrder = os
              state_to :pending_flat, "#{armt} Stop order was hit at #{os.execPrice}"
            else # Something Fishy (order was perhaps cancelled????
              raise WatcherException.new("#{now} Stop Order in unexpected state #{os.orderStatus}!!")
            end

          else # paper trading
            state_to :pending_flat, "#{armt} hit stopout #{@stopOut} -- going flat!" if m.dstop <= 0
          end
          
          # Check now to see if we need to upgrade stopout. 
          # We shall upgrade to even when point profit is met.
          unless m.upEven
            if m.dpoint >= @stop_off_even
              transmitStatusUpdate "#{armt} Ready to upgrade stopout. Upgrade to Even hit(#{m.dpoint})."
              m.upEven = true
            end
          else # general upgrade check
            # Adjust sigmoid
            m.sig = SIGMOID_BOT \
            + (SIGMOID_TOP - SIGMOID_BOT) * [(Time.now - @strikeTime) / (@hour_sigmoid * 3600),
                                             1.00].min
            # now we compute the d stop-out adjustment on the basis of m.sig
            m.dsoa = m.dpointPeak * m.sig
            @newStopOut = ((@strike + m.dsoa * lsfactor) / @tickq).round(0) * @tickq
            unless (@newStopOut - @stopOut) * lsfactor <= 0
              ssig = sprintf "%4.3f", m.sig
              transmitStatusUpdate "#{armt} Upgrading stopout of our #{lors} trade to #{@newStopOut}. Sigmoid is #{ssig}."
              m.state = :upgrade_stopout 
            end
          end        
          
        when :upgrade_stopout
          # @newStopOut is what we are upgrading to.
          # @stopOut is what we are upgrading from.
          if armed?
            # Issue modification orders to upgrade the stopout.
            @orderIDStop = modifyBrokerOrder(:exit, @orderIDStop, @future_broker, 
                                             @contracts, 0, @newStopOut)
          end

          @stopOut = @newStopOut
          m.state = :checking          
        end

      rescue MarketException
        p $!
        puts $!.backtrace.join("\n")
        state_to :failed, $!
      end
    end

    # Pending Flat -- exit a trade, or note the stopout of a trade.
    #
    # Note that in getting here, it may have been becasue GO FLAT was
    # clicked; or :hot found an exit condition, or a stop-out was hit
    # in a live trade. 
    #
    # Pending Flat must be intelligent enough to discern what is going
    # on here and take the proper measures.
    #
    # in case Pending Flat must exit a live trade, said exit shall be governed
    # by a mini state machine. Simple enough -- just keep checking until the trade
    # is exited.
    def do_pending_flat(m)
      begin
        case m.state
        when nil # setup
          if armed?
            # Either this was a stopout, or
            # the user clicked GO FLAT. If GO FLAT was clicked, we must
            # use a simple micro-state machine to exit the trade.
            # 
            # If this was actually stopped out, then the @stopOrder
            # should contain the orderStatus, which will have in it the
            # all-important exit price.
            #
            # We also must check the Positions to ensure this order really
            # was exited  and that there are no more outstanding positions
            # for that instrument.

            unless @stopOrder.nil?
              # Order was stopped out
              calculateProfitLoss true, @stopOrder.execPrice
              m.state = :exited
            else
              # User clicked 'Go Flat'. Cancel the stop and issue an exiting market order.
              cancelBrokerOrder(@orderIDStop)
              @orderIDExit = placeBrokerOrder(:exit, @future_broker, @contracts)
              transmitStatusUpdate "#{armt} Issued a market order to exit position. Checking..."
              m.state = :check_exit_order
            end
          else # paper trade.
            calculateProfitLoss true
            m.state = :exited
          end

        when :check_exit_order # should only be here if armed!!!!!!
          os = getOutstandingOrders(nil, nil, @orderIDExit)[0]
          # (in)sanity checks!!!
          raise MarketException.new("Cannot find stop order##{@orderIDStop} for going flat!!!") if os.nil?
          case os.orderStatus
          when OSS_OPEN
            # Do nothing. Order has not filled yet.

          when OSS_FILLED # Market order was filled!
            calculateProfitLoss true, os.execPrice
            transmitStatusUpdate "#{armt} Market Order executed at #{os.execPrice}"
            m.state = :exited

          when OSS_CANCELLED
            raise MarketException.new("Exit Order #{@orderIDExit} has been unexpectely cancelled!!!")
          end

        when :exited           
          state_to :flat, "#{armt} We're flat now!!!!!!"

        else
          raise MarketException.new("BUG!!! Unknown microstate #{m.state}")
        end
      rescue MarketException
        p $!
        puts $!.backtrace.join("\n")
        state_to :failed, $!
      end
    end

    def do_flat(m)
      begin        
        # One final sanity check -- we should have NO Outstanding positions!!!!
        if armed?
          unless getOutstandingPositions(@future_broker).empty?
            raise MarketException.new("#{armt} DANGER!!! WE STILL HAVE AN OUTSTANDING POSITION on #{@future_broker}!!!!!!")
          end
        end
        bell_exited_position
        state_to :dormant, "Completed all sanity checks. Ready to trade again!"
      rescue MarketException
        p $!
        puts $!.backtrace.join("\n")
        state_to :failed, $!
      ensure
        # I am anal and paranoid about this @stopOrder being set to nil at this point!!!
        @stopOrder = nil
      end
    end

    def do_pending_half_flat(m)
    end

    #= Reversing a hot trade.
    # In a hot trade, there will be the position
    # and the stop-out.
    #
    # The first thing we must do is kill off the stop-out, then reverse the trade by
    # doing a reverse order at twice the number of contracts.
    # 
    # Once that is done, we must set up and establish a new stopout,
    # submit that, and transistion back to hot.
    #
    # The reversal will have some aspects of going flat, because
    # we need to update the accounting. Functionally, the reversal
    # shall be treated as a new trade, with the old one concluded 
    # at the actual fill price of the reversal.
    #
    # Pending_reversal:
    #
    #- Kill the stopout
    #- Transistion to reversal
    #
    def do_pending_reversal(m)
      begin
        if armed?
          cancelBrokerOrder(@orderIDStop)
          transmitStatusUpdate("#{armt} broker order #{@orderIDStop} cancelled")
          @orderIDStop = nil
        end
        state_to :reversal, "#{armt} Reversing..."
      rescue MarketException
        p $!
        puts $!.backtrace.join("\n")
        state_to :failed, $!
      end
    end

    #= Reversal
    # There is, as of now, just the position and no stop.
    #
    #- Issue a placement at -2 @contracts
    #- Wait to see and confirm that order took place
    #- Put in a new stopout, and @contract = -@contracts
    #- update accounting accordingly (a bit of the go_flat stuff)
    #- transistion to hot
    def do_reversal(m)
      go_hot = lambda {
        fresh_state_to :hot, "#{armt} Going hot on a #{lors} reversed trade at #{@strike} with new stopout of #{@stopOut}"
      }
      begin
        case m.state
        when nil # first time in
          if armed?
            @orderIDEntry = placeBrokerOrder(:reversal, @future_broker, @contracts)
            transmitStatusUpdate("#{armt} Reversal market order #{@orderIDEntry} placed.")
            m.state = :check_reversal
          else # paper trading
            m.quote = @quote
            calculateProfitLoss true, m.quote.last
            @contracts = -@contracts
            setStrike m.quote.last
            @stopOut = if long?
                         m.quote.last - @stop_off
                       elsif short?
                         m.quote.last + @stop_off
                       else
                         raise MarketException.new("You can't have zero contracts, silly!")
                       end
            go_hot.()
          end          
          
        when :check_reversal
          if armed?
            os = getOutstandingOrders(nil, nil, @orderIDEntry)[0]
            # Insanity check
            raise MarketException.new("Where is the friggin order???") if os.nil?
            case os.orderStatus
            when OSS_OPEN # not filled yet
              # do nothing.
            when OSS_FILLED # Yay! Filled! Place our stopout!             
              # close out previous order
              m.strike = m.exit = os.execPrice
              calculateProfitLoss true, m.exit
              
              # Reverse
              @contracts = -@contracts
              setStrike m.strike

              # Set up stop
              @stopOut = if long?
                           m.strike - @stop_off
                         elsif short?
                           m.strike + @stop_off
                         else
                           raise MarketException.new("Something is hideously wrong: ZERO CONTRACTS!")
                         end
              @orderIDStop = placeBrokerOrder(:exit, @future_broker, @contracts, 0, @stopOut)
              bell_filled
              transmitStatusUpdate  "#{armt} Order is now filled. Placing Stop at #{@stopOut} "
              m.posCheckCount = 0
              m.state = :check_stop_order              
            else # Something smells rotten in Denmark.
              raise MarketException.new("#{armt} Unknown Order Status #{os.orderStatus} for order ##{@orderIDEntry}")
            end
          end  

        when :check_stop_order
          if armed?
            # Checking our stop order!!!

            os = getOutstandingOrders(nil, nil, @orderIDStop)[0]
            #More (in)Sanity Checks!!!!
            raise MarketException.new("Can't find our order!!!!?!") if os.nil?
            
            # This is simple -- the stop order should be in the OSS_OPEN state.
            case os.orderStatus
            when OSS_OPEN
              # All is well with the world. Now pull position and get the REAL strike price!
              @position = po = getOutstandingPositions(@future_broker)[0]
              
              # Even more(in)Sanity Checks!!!!!!
              unless po.nil?
                transmitStatusUpdate("#{armt} We were filled on #{po.symbol} at #{po.strikePrice}")
                setStrike m.strike # m.strike set in :check_entry_order->OSS_FILLED microstate!
                go_hot.()
              else # either the position status has not been updated yet, or there is another problem
                m.posCheckCount += 1
                raise MarketException.new("WTF? Can't get the POSITION Information!!!!") unless m.posCheckCount < MAX_POS_CHECK_COUNT 
              end
              
            else # Somethins is fishy.
              raise MarketException.new("#{armt} Stop Order Status is unexpectly #{os.orderStatus}")
            end            
          else # paper trading? Should not be here!
            raise MarketException.new "Illegal Microstate for #{armt} "
          end          
        else # illegal state for an unarmed order!!1
          raise MarketException.new "ILLEGAL MICROSTATE #{m.state} for #{armt}"
        end

      rescue MarketException
        p $!
        puts $!.backtrace.join("\n")
        state_to :failed, $!
      end
    end
  
    def do_failed(m)
      if m.bell.nil?
        bell_error
        m.bell = true
      end
    end

    # Kill off all outstanding orders!
    # 
    # When armed, an attempt shall be made to cancel pending orders.
    # if any should fail, that probably means the order was filled.
    # We'll then have to check the status of the failed cancel, and
    # if filled, we must revert to the pending_entry macrostate.
    #
    # Even though seeking_entry can transistion here, we'd never transistion
    # back to seeking_entry, because at that point no orders have been placed.
    # Seeking entry is more of a sanity-check to see if any outstanding orders
    # exist prior to generating a new one.
    # 
    ## NOTE WELL
    ##
    ## There is currently a potential for a race condition between when
    ## the check for positions and where orders are canceled. It is possible
    ## that something may be filled in that short sliver of a time. Currently,
    ## the state machine will fail somewhere, but we really wish to structure
    ## this so that the race condition is taken care of.

    def do_pending_panic(m)
      begin
        if armed?
          case m.state
          when nil
            unless getOutstandingPositions(@future_broker).empty?                
              bell_reverting                
              state_to :pending_entry, "#{armt} Order for #{@future_broker} has been filled. Reverting."
            else              
              # Cancel ALL Open and Pending orders!
              # FIX!!! Race condition is possible between ghe getOutstandingPositions() check 
              #        and here!
              getOutstandingOrders(@future_broker, OSS_OPEN).each { |os|
                transmitStatusUpdate "#{armt} Killing order #{os.orderID}"
                cancelBrokerOrder(os.orderID)
              }
              m.check_counter = 0
              m.state = :check_cancelled
            end
                        
          when :check_cancelled
            # We simply keep checking until we get no more open orders.
            if getOutstandingOrders(@future_broker, OSS_OPEN).empty?
              # Just in case -- check to see if their is an open position. If so,
              # we need to revert back to :pending_entry.              
              unless getOutstandingPositions(@future_broker).empty?                
                bell_reverting                
                state_to :pending_entry, "#{armt} Order for #{@future_broker} has been filled. Reverting."
              else
                state_to :panic, "#{armt} All Orders have been exited."
              end
            end

            m.check_counter += 1           
            if m.check_counter > 200
              raise MarketException.new("Timeout Warning: Taking too long to exit orders!!!!")
            end

          else # Microstate problem!!!!
            raise MarketException.new("BUG!!!!! Unexpected microstate #{m.state}")
          end

        else # paper trade
          state_to :panic, "#{armt} All Orders have been exited."          
        end     
      rescue MarketException
        p $!
        puts $!.backtrace.join("\n")
        state_to :failed, $!
      end
    end


    # All have been killed off.
    def do_panic(m)
      if armed?
        # TODO: Make the necessary logs and houskeeping cleanup
        # (do we really have anything to do here?)
      end
      state_to :dormant, "#{armt} Cleanup completed."
    end
  end
end

=begin rdoc
=The Bollinger Watcher
=end
module Bollinger
  include WatcherFramework
end


=begin rdoc
=The MovingAve Watcher

Manages a trade by following multiple Moving Averages on
different timeframes.

=end
module MovingAve
  include WatcherFramework
end

=begin rdoc
=The Smarty Watcher

The Smarty Watcher employes a number of techniques to
follow the Seven Sisters -- Bollingers and Moving Averages --
to manage a trade. Will watch trade on multiple timeframes.

=end
module Smarty
  include WatcherFramework
end
