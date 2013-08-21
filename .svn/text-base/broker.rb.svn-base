# Broker Interface

require 'fox16'
require 'xml2ob'
require 'net/http'
require 'net/https'
require 'uri'
require 'postman'
require 'market'
require 'funnel'
require 'pp'

include MarketFC

=begin rdoc
=Orders -- Order Mixin for creating Order Objects

Even though you don't see it documented here, there are 3 order macros:

- order(symbol, action, quantity, orderType, tif = TIF_DAY, limitPrice = nil, stopPrice = nil)
- order1(symbol, action, quantity, orderType, tif = TIF_DAY, limitPrice = nil, stopPrice = nil)
- order2(symbol, action, quantity, orderType, tif = TIF_DAY, limitPrice = nil, stopPrice = nil)

The order macros are for use with:
 Brokers::Broker#placeOrder(), 
 Brokers::Broker#placeOrderTriggersOrder(), and 
 Brokers::Broker#modifyOrder()
on the Broker-derived object.

Use the order() macro with  placeOrder() and  modifyOrder(), and the order1() and order2()
macros with placeOrderTriggersOrder() (and with placeOrderCancelsOrder() if we ever implement 
this).
=end
module Orders
  # Order Actions
  OA_BUY = "BUY"
  OA_SELL = "SELL"
  # FIX!!!! We've changed these codes until we can figure out what they should REALLY be!
  OA_SHORT = "SELL" #"SHRT"
  OA_COVER_SHORT = "BUY" # "BTOC"

  # Order types
  OT_MARKET = "MARKET"
  OT_LIMIT = "LIMIT"
  OT_STOP = "STOP"
  OT_STOP_LIMIT = "SOTP_LIMIT"
  OT_MARKET_ON_CLOSE ="MKT_CLOSE"

  # Order Routes
  OR_NBBO = "NBBO" # National Best Bid or Offer (default)
  OR_CBOE = "CBOE"
  OR_AMEX = "AMEX"
  OR_PHLX ="PHLX"
  OR_ISE = "ISE"
  OR_BOX = "BOX"

  # Order Time in Force
  TIF_DAY = "DAY"
  TIF_GTC = "GTC"

  # Order All or Nothing
  AON_TRUE = "True"
  AON_FALSE = "False"

  # Order Status (for Broker#getOrderStatus)
  OSS_FILLED = "Filled"
  OSS_CANCELLED = "Cancelled"
  OSS_OPEN = "Open"
  OSS_CANCEL_PENDING = "Cancel Pending"
  OSS_EVERYTHING = nil

  # AdvancedOrderType (for PlaceGenericOCOOTOOrder)
  OTO_STOCK ="OTO_STOCK"
  OTO_OPTION = "OTO_OPTION"
  OTO_FUTURES="OTO_FUTURES"
  OTO_STOCK_OPTION="OTO_STOCK_OPTION"
  OCO_STOCK="OCO_STOCK"
  OCO_OPTION="OCO_OPTION"
  OCO_FUTURES="OCO_FUTURES"

  # Unsupported advance types
  OTOC_STOCK="OTOC_STOCK"
  OTOC_OPTION="OTOC_OPTION"

  # Advanced Orders for PlaceCNTOOrder
  CNTO_STOCK = "CNTO_STOCK"
  CNTO_OPTION = "CNTO_OPTION"
  CNTO_STOCK_OPTION = "CNTO_STOCK_OPTION"
  CNTO_OPTION_STOCK = "CNTO_OPTION_STOCK"
  

  [[:order,
    "sSymbol:",
    "sAction:",
    "dQty:",
    "nil =>",
    "nil =>",
    "sTIF:",
    "sOrderType:",
    "dLimitPrice:",
    "dStopPrice:",
    "nil =>"
   ],
   [:order1,
    "sFirstOrderSymbol:",
    "sFirstOrderAction:",
    "sFirstOrderQty:",
    "sFirstOrderQtyType:",
    "sFirstOrderAON:",
    "sFirstOrderTIF:",
    "sFirstOrderType:",
    "sFirstOrderLimitPrice:",
    "sFirstOrderStopPrice:",
    "sFirstOrderRoute:",
   ],
   [:order2,
    "sSecondOrderSymbol:",
    "sSecondOrderAction:",
    "sSecondOrderQty:",
    "sSecondOrderQtyType:",
    "sSecondOrderAON:",
    "sSecondOrderTIF:",
    "sSecondOrderType:",
    "sSecondOrderLimitPrice:",
    "sSecondOrderStopPrice:",
    "sSecondOrderRoute:",
   ]].each do
    |order, sSymbol, sAction, dQty, qtyType, aon, sTIF, sOrderType, dLimitPrice, dStopPrice, route |

    module_eval %{
      # #{order} fuction is a 'macro' to generate an order hash for the placeXXX () methods.
      def #{order} (symbol, action, quantity, orderType, 
                    limitPrice = nil, stopPrice = nil, 
                    tif = TIF_GTC)
         \{
           #{sSymbol} symbol,
           #{sAction} action,
           #{dQty} quantity,
           #{qtyType} nil,
           #{aon} nil,
           #{sTIF} tif,
           #{sOrderType} orderType,
           #{dLimitPrice} limitPrice,
           #{dStopPrice} stopPrice,
           #{route} nil
         \}
      end
    }
  end
end

=begin rdoc

=Broker -- Standard Broker Functionality

All Broker objects shall have the same -- or close to it --
interface. For now, we are mainly concerned with OptionsXpress, but
we may do others in the future.

==Orders Mixin
In the Orders mixin are constants and 3 macros you'll need with some of the
method calls on the Brokers object. Please see Orders for the details.
=end
module Brokers 
  include Fox

  # Taken from the C++ code.
  # Create a selector from the type and id
  def FXSEL(type, id) 
    (id & 0xffff) | (type << 16)
  end
  
  #fxdefs.h:#define FXSELTYPE(s) ((FX::FXushort)(((s)>>16)&0xffff))
  #fxdefs.h:#define FXSELID(s) ((FX::FXushort)((s)&0xffff))

  class BrokerException < Exception
  end

  # Monitor Log Message Attributes
  MON_MASK = 0x00FF  # Mask for the following exclusive messages
  MON_NOTICE = 0     # Geneal message
  MON_WARNING = 1    # Something is not quite bloddy right, so keep an eye.
  MON_ERROR = 2      # Something totally screwed up.
  MON_IMPORTANT = 3  # Ye should pay CLOSE ATTENTION TO THIS. 

  # These may be ORed in to yield additional information
  MON_BROKER   = 0x0100 # Message came from Broker (as opposed to our interface)
  MON_NETWORK  = 0x0200 # Network-related message
  MON_SOFTWARE = 0x0400 # Software-related

  # All Broker objects derive from this.
  # 
  # Note that on most getXXX() functions, they all take optionally a block.
  # If the block is given, then that automatically registers the block for
  # peroidic updates.
  #
  # In the case the block is given, the block is also returned, as it will be  needed
  # to unregister.
  class Broker < Market
    include Postman

    attr_reader :username, :accountNumber, :person
    attr_writer :target

    @@monitorLog = []
    @@newLogs = true

    # 
    def initialize
      super
      @log_mt = :broker_log
      @gui_mt = :gui_update
    end

    # "Dummy" login (well, stores the Username and Password)
    # You will need to implement this in the subclass.
    #
    # Stores the username and password in this class instance.
    # This may be not a good practice, but  necessary to allow
    # us to maintain the login status in the subclass.
    #
    # If username and password are not given, does not change anything.

    def login(username = nil, password = nil)
      @username = username unless username.nil?
      @password = password unless password.nil? # WARN: Should we be storing the pw in the class instance?
    end

    # Destroy login information. 
    # This should be called by subclass.
    def logout
      @username = @password = nil
    end
    
    # Get a list of strings describing the monitor status.
    def monitorStatus
      @@newLogs = false
      @@monitorLog
    end

    def statusChanged?
      @@newLogs
    end

    # Get Position information on customer. Must be implemented by subclass.
    # the block is optional, and should return the object instead of the block
    # if not given.
    def getPositions(&block)
      raise BrokerException.new("Not Implemented Yet")
    end
    
    # Unregister the lister for positions.
    def unregPositions(block)
      raise BrokerException.new("Not Implemented Yet")
    end

    # Get Data on a particular future.
    def getFuturesData(future)
      raise BrokerException.new("Not Implemented Yet")
    end

    # Get Position information on customer. Must be implemented by subclass.
    # The startDate and endDate objects are Date or DateTime objects.
    # 
    # If a date is not given, the current date will be the default.
    def getActivity(startDate = Time.new, endDate = nil, &block)
      raise BrokerException.new("Not Implemented Yet")
    end

    # Get the status of orders.
    # We have no clue what dateRange means
    def getOrderStatus(status = nil, dateRange = 0, securityType = nil, &block)
      raise BrokerException.new("Not Implemented Yet")
    end

    def unregActivity(block)
      raise BrokerException.new("Not Implemented Yet")
    end

    def placeOrder(order)
      raise BrokerException.new("Not Implemented Yet")
    end    
   
    # Place 2 orders such that the execution of the first order
    # triggers the 2nd order. 
    #
    # Use order1() and order2() macros to generate the two orders.

    def placeOrderTriggersOrder(order1, order2)
      raise BrokerException.new("Not Implemented Yet")
    end

    def cancelOrder(orderID)
      raise BrokerException.new("Not Implemented Yet")
    end

    # Cancle the given orderID, and create a new (modified) order.
    # Use the order() macro to do this.

    def modifyOrder(orderID, order)
      raise BrokerException.new("Not Implemented Yet")
    end

    def getCustomerBalance()
      raise BrokerException.new("Not Implemented Yet")
    end
  end

  # OptionsXpress Driver for Broker.
  # Handles all the pecularities related to the OptionsXpress connection.
  class OptionsXpress < Broker
    include XML2Ob
    include Funnel
    include Translate

    # seconds to refesh login status.
    REFRESH_LOGIN_PERIOD = 1800 

    attr_reader :sessionID, :sourceID
    
    # Translate OptionsXpress fields to Embracer fields!
    @@MAPPER = {
      aON: nil,
      accntNum: nil,
      accountID: lambda {|k,v| [:accountID, v.to_s]},
      action:  lambda {|k,v| [:action, v]},
      ask: lambda {|k,v| [:ask, v.to_f]},
      bid: lambda {|k,v| [:bid, v.to_f]},
      change: nil,
      close: nil,
      contractSize: lambda {|k,v| [:pointPrice, v.to_f]},
      costBasis: nil,
      cumQty: nil,
      cusipNumber: nil,
      customerViewOnly: nil,
      displayDenominator: nil,
      displayInTick: nil,
      email: nil,
      errorCode: nil,
      exchFee:  lambda {|k,v| [:exchFee, v.to_f]},
      exchange: nil,
      exchangeFee:  lambda {|k,v| [:exchangeFee, v.to_f]},
      execPrice:  lambda {|k,v| [:execPrice, v.to_f]},
      expMonth: nil,
      expYear: nil,
      expirationDate: nil,
      expirationMonth: nil,
      expirationYear: nil,
      fillTime: lambda{|k, v| d, t = v.split 'T'; t, crap = t.split '.'; [[:fDate, d], [:fTime, t]]},
      fullName: nil,
      gainLoss: lambda {|k,v| [:profit, v.to_f]},
      goalPercentageGain: nil,
      goalPercentageLoss: nil,
      high:  lambda {|k,v| [:high, v.to_f]},
      insertDate:  lambda{|k, v| d, t = v.split 'T'; t, crap = t.split '.'; [[:iDate, d], [:iTime, t]]},
      internalOrder: nil,
      isCombo: nil,
      last: lambda {|k,v| [:last, v.to_f]},
      limitPrice:  lambda {|k,v| [:limit, v.to_f]},
      localCode: nil,
      low: lambda {|k,v| [:low, v.to_f]},
      marginMaintenance: nil,
      marginRequirements: nil,
      marketId: nil,
      message: lambda {|k, v| [:message, v.to_s] },
      nFAFee: nil,
      optionRoot: nil,
      orderID: lambda {|k, v| [:orderID, v.to_i] },
      orderStatus: lambda {|k, v| [:status, v.to_s] },
      orderType: nil,
      orderTypes: nil,
      parentOrderID: nil,
      personID: nil,
      positionID: lambda {|k, v| [:positionID, v.to_s] },
      price:  lambda {|k,v| [:price, v.to_f]},
      priceFormat: nil,
      productDescription: nil,
      putOrCall: lambda {|k,v| [:type, v]},
      quantity: lambda {|k,v| [:contracts, v.to_i]},
      quoteHasData: nil,
      route: nil,
      securityType: nil,
      sessionEndTime: nil,
      sessionStartTime: nil,
      spreadID: nil,
      stopPrice:  lambda {|k,v| [:stop, v.to_f]},
      strikePrice: lambda {|k,v| [:strike, v.to_f]},
      symbol: lambda {|k,v| [:symbol, v.to_s]},
      symbolDescr: lambda {|k,v| [:description, v.to_s]},
      tIF: nil,
      tickSize:  lambda {|k,v| [:tickq, v.to_f]},
      timingServiceID: nil,
      underlyingAsk: nil,
      underlyingBid: nil,
      underlyingDescription: nil,
      underlyingLast: nil,
      underlyingSecurity: lambda {|k,v| [:underlying, v]},
      underlyingSymbol: nil,
      userID: nil,
      value: nil,
      volume: lambda {|k,v| [:volume, v.to_i]},
      optionmultiplier: nil,
      lOrderID: lambda {|k,v| [:orderID, v.to_i]},
      sMessage: lambda {|k, v| [:message, v.to_s] },
      sError: lambda {|k, v| [:error, v.to_s] },
    }

    # We set up the HTTPS SSL transaction stuff here. See page #503 of the Cookbook.
    def initialize 
      super
      logout # to initialize the fields to nil.

      @acctURI = URI.parse("https://oxbranch.optionsxpress.com/accountservice/account.asmx")
      @orderURI = URI.parse("https://oxbranch.optionsxpress.com/accountservice/order.asmx")
      @sourceID = "IN3105" # This is my personal source ID -- should we even have this hard-coded? FIX!!!!
      @acctReq = Net::HTTP.new(@acctURI.host, @acctURI.port)
      @orderReq = Net::HTTP.new(@orderURI.host, @orderURI.port)
      @acctReq.use_ssl = @orderReq.use_ssl = true
      @acctReq.verify_mode = @orderReq.verify_mode = OpenSSL::SSL::VERIFY_NONE      

      @thr = Thread.new { _runner }
      @thrQueue = {}
    end

    # This runs in a seperate thread.
    def _runner
      loop {
        sleep(0.5)
        @thrQueue.clone.each {|target, work|
          begin
            work.(target)
          rescue
            puts "(OX) Target #{target} is being removed because..."
            p $!
            puts $!.backtrace.join("\n")
            @thrQueue.delete target
          end
        }
      }
    end
    private :_runner

    # Unregister receiver of updates.
    def unreg(target)
      @thrQueue.delete(target)
    end

    # Internal request (do not call this directly).
    # returns an object holding the results.
    # all args besides the first three follow the ":field => val" convention.
    def _request(meth, uri, req, *hargs)
      path = "#{uri.path}/#{meth}?#{h2get(hargs[0])}"
      puts path if $debug
      open("xml.log", "a") { |f|
        f << "*" * 50
        f << "#{Time.now}\n"
        f << path
        f << "\n"
      } if $logxml
      convert(req.get(path).body) unless $trap
    end
    private :_request

    # Make an account request to OptionsXpress. This is a "low-level" interface;
    # do not call this directly outside of this class.
    def accountRequest(meth, *args)
      _request(meth, @acctURI, @acctReq, *args)
    end

    # Make an order request to OptionsXpress. This is a "low-level" interface;
    # do not call this directly outside of this class.
    def orderRequest(meth, *args)
      _request(meth, @orderURI, @orderReq, *args)
    end
    
    ## Log user into OptionsXpress
    # You may call this subsequently without any parameters to "relogin" or to
    # keep the session fresh.
    #
    ## Postman Messages
    # :broker_log => [:notice | :error], text
    # :gui_update => :login, [:pending | :success | :fail]
    def login(username = nil, password = nil)
      super(username, password) # stores this in the class instance
      @loginTime = Time.new
      puts "#{username} logging in"
      o = accountRequest(:GetOxSessionWithSource, 
                         :sUserName => @username,
                         :sPassword => @password,
                         :sSessionID =>'',
                         :sSource => @sourceID).cAppLogin
      p o
      # Now, try to determine if login was successful or not.
      unless o.errorMsg.nil?
        transmit(:broker_log, :error, "OptionsXpress Login failure for #{@username}.")
        transmit(:gui_update, :login, :fail)
        raise BrokerException.new(o.errorMsg) 
      end

      transmit(:broker_log, :notice, "User #{@username} is now logged into OptionsXpress.")
      transmit(:gui_update, :login, :success)
      @sessionID = o.sessionID
      @person = "#{o.FirstName} #{o.LastName}"
      @accountNumber = o.AccountNum
      @accountID = o.accountID
      o
    end

    # Call this before all OX access to the API, to make sure
    # we still have a valid login.    
    def refreshLogin
      login unless Time.now - @loginTime < REFRESH_LOGIN_PERIOD
    end

    def logout
      super
      @sessionID = @person = @accountNumber = @accountID = nil
    end

    def loggedIn?
      !@sessionID.nil?
    end   
    
    # Get Position information on customer. 
    # Returns an array of position objects.
    #
    # https://oxbranch.optionsxpress.com/accountservice/account.asmx?op=GetCustPositions
    def getPositions(&block)
      refreshLogin
      if block.nil?
        pos = translate(accountRequest(:GetCustPositions, sSessionID: @sessionID), 
                        @@MAPPER).arrayOfCServPosition.cServPosition
        pos = [pos] unless pos.kind_of? Array
        pos
      else # Set up for regular notifications.
        target = wrap block
        @thrQueue[target] = lambda { |t| t.(getPositions()) }
        target
      end
    end
    alias_method :unregPositions, :unreg

    # Get Data on a particular future.
    def getFuturesData(future)
      refreshLogin
      translate(orderRequest(:GetFuturesData, 
                             sSessionID: @sessionID,
                             sSymbol: future), 
                @@MAPPER).utFuturesDataResults
    end

    ACT_DATE_FORMAT = "%m/%d/%Y"

    # Get Account Activity on customer. The startDate and endDate objects 
    # are Date, Time, or DateTime objects.
    #
    # If the endDate is nil, will always use the current date as the endDate.
    #
    # This calls GetCustActivity of the OX API.
    # https://oxbranch.optionsxpress.com/accountservice/account.asmx?op=GetCustActivity
    def getActivity(startDate = Time.new, endDate = nil, &block)
      refreshLogin
      if block.nil?
        dstart = startDate.strftime(ACT_DATE_FORMAT)
        dend = unless endDate.nil?
                 endDate.strftime(ACT_DATE_FORMAT)
               else
                 Time.new.strftime(ACT_DATE_FORMAT)
               end
        act = translate(accountRequest(:GetCustActivity, 
                                       sSessionID: @sessionID,
                                       datStartDate: dstart,
                                       datEndDate: dend),
                        @@MAPPER).arrayOfCServActivity.cServActivity
        act = [act] unless act.kind_of? Array
        act
      else
        target = wrap block
        @thrQueue[target] = lambda { |t| t.(getActivity(startDate, endDate)) }
        target
      end
    end  
    alias_method :unregActivity, :unreg

    # Get status of orders.
    #
    # We have no idea what dateRange means, except that we get back
    # today's order for 0, lots of past orders for anything over 9, and 
    # some orders between 1 and 9.
    # 
    # Status can be:
    ## Filled
    ## Cancelled
    ## Open
    ## Cancel Pending
    ##
    ## See Orders for the constants defining the above.
    #
    # See: https://oxbranch.optionsxpress.com/accountservice/account.asmx?op=GetCustOrderStatus
    def getOrderStatus(status = nil, dateRange = 100, securityType = nil, &block)
      refreshLogin
      if block.nil?
        os = translate(accountRequest(:GetCustOrderStatus,
                                      sSessionID: @sessionID,
                                      sStatus: status,
                                      iDateRange: dateRange,
                                      sSecurityType: nil,
                                      sSortDir: nil,
                                      sSortField: nil),
                       @@MAPPER).arrayOfCServOrder.cServOrder
        os = [os] unless os.nil? or os.kind_of? Array 
        os
      else
        target = wrap block
        @thrQueue[target] = lambda { |t| t.(getOrderStatus(status, dateRange, securityType)) }
        target
      end
    end

    # Use the Orders#order() macro in creating the order hash needed for the parameter.
    def placeOrder(order)
      refreshLogin
      # p rehash(*order, sSessionID: @sessionID)
      translate(orderRequest(:PlaceFuturesOrder, 
                             *rehash(order, sSessionID: @sessionID)),
                @@MAPPER).utOrderReturnData
    end    
   
    # Place 2 orders such that the execution of the first order
    # triggers the 2nd order. 
    #
    # Use order1() and order2() macros to generate the two orders.

    # Use the Orders#order1() and Orders#order2()  macros in 
    # creating the order hashes needed for these parameters.
    def placeOrderTriggersOrder(order1, order2)
      refreshLogin
      r = orderRequest(:PlaceGenericOCOOTOOrder, 
                       *rehash(order1.merge(order2), sSessionID: @sessionID)
                       ).utAdvancedOrderReturnData
      r.orderIDs = r.lOrderID.map { |l| l.long } if r.lOrderID.kind_of? Array
      r._hash.delete(:lOrderID)
      translate(r, @@MAPPER)
    end

    # Cancel an outstanding order
    def cancelOrder(orderID)
      refreshLogin
      translate(orderRequest(:CancelSingleOrder, 
                             sSessionID: @sessionID, lOrderID: orderID),
                @@MAPPER).utOrderReturnData
    end

    # Cancle the given orderID, and create a new (modified) order.
    # Use the order() macro to do this.
    def modifyOrder(orderID, order)
      translate(orderRequest(:CancelReplaceSingleOrder, 
                             *rehash(order, sSessionID: @sessionID, lOrderID: orderID)),
                @@MAPPER).utOrderReturnData
    end

    # Get the balance information on a customer's account.
    def getCustomerBalance()
      refreshLogin
      translate(accountRequest(:GetCustBalance, sSessionID: @sessionID),
                @@MAPPER).cAppBalance
    end
  end # OptionsXpress class

end

# Utility functions
# Take the last two entries, and if they are hashes, combine them.
def rehash(*pa)
  if (pa.length >= 2 && pa[-1].class == Hash && pa[-2].class == Hash)
    pa[-2].merge!(pa[-1])
    pa.delete_at(-1)
  end
  pa
end

# Change a hash into a get string.
def h2get(h) 
  s = []
  h.each { |k, v|
    s.push("#{k}=#{v}")
  }
  s.join('&')
end
