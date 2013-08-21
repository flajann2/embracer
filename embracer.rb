#!/usr/local/bin/ruby

require 'fox16'
require 'fox16/colors'
require 'xml2ob'
require 'drb/drb'
require 'yaml'
require 'broker'
require 'iqfeed_datafeed'
require 'application'
require 'funnel'
require 'watcher'
require 'bells'
require 'emwidgets'
require 'mongo'
require 'eostruct'

include Fox
include Brokers
include Datafeed
include Application

# Application
class EmbracerApp < App
  @@FN_CREDENTIALS = "credentials.y"
  @@FN_CONFIG = "configuration.y"
  @@FN_SETTINGS = "settings.y"

  # Application assists (connections to external resources)
  attr_reader :broker
  attr_reader :quotes
  attr_reader :historical

  # Application state (persisted)
  attr_reader :credentials
  attr_reader :configuration
  attr_reader :settings
  attr :layout

  # Application Fonts
  attr_reader :bigFont
  attr_reader :normalFont
  attr_reader :smallFont

  # Mongo DB
  attr_reader :db

  # FOX application
  attr_reader :app

  def initialize
    super
    @app = FXApp.new("Embracer", "LRC")

    @db = Mongo::Connection.new("amalthea").db("embracer")
    
    # insure that certain indicies are set up
    @db[:orders].create_index([
                                [:orderID, Mongo::ASCENDING],
                                [:time, Mongo::ASCENDING],
                               ])
    @db[:defaults].create_index([[:name, Mongo::ASCENDING]],
                                 unique: true)
    
    class << @app
      def exit(code = 0)
        puts "Exiting the application."
        appEM.save_settings
        appEM.save_layout(appEM.settings[:layout_file])

        appEM.broker.logout
        appEM.quotes.logout
        super(code)
      end
    end

    # Assitive Objects
    @broker = OptionsXpress::create
    @quotes = DRbObject.new_with_uri($qserverURI)
    @historical = DRbObject.new_with_uri($hserverURI)

    # Application State
    @credentials = {} # login credentials for a numbef of issues
    @configuration = {} # Application settings (name: value pairs)
    @settings = {} # Application settings (name: value pairs)
    @layout = [] # Array of layout objects

    # Application fonts
    @bigFont = FXFont.new(@app, "courier", 12, FONTWEIGHT_BOLD)
    @normalFont = FXFont.new(@app, "courier", 10, FONTWEIGHT_BOLD)
    @smallFont = FXFont.new(@app, "courier", 8, FONTWEIGHT_BOLD)
  end

  # Load credentials, configuration and settings, if present
  def load_settings
    begin
      open(@@FN_CREDENTIALS, "rb") { |fd| @credentials = YAML::load(fd.read) 
      } if File.exists? @@FN_CREDENTIALS
      appEM.broker.login(@credentials[:broker_user], @credentials[:broker_pass])
      appEM.quotes.login(@credentials[:datafeed_user], @credentials[:datafeed_pass])
      
      open(@@FN_CONFIG, "rb") { |fd| @configuration = YAML::load(fd.read) 
      } if File.exists? @@FN_CONFIG
      open(@@FN_SETTINGS, "rb") { |fd| @settings = YAML::load(fd.read) 
      } if File.exists? @@FN_SETTINGS
    rescue BrokerException => be
      print "load_settings() failed: #{be}"
    end
  end

  # Save credentials, configuration and settings
  def save_settings
    open(@@FN_CREDENTIALS, "wb") { |fd| fd.write(YAML::dump(@credentials)) }
    open(@@FN_CONFIG, "wb") { |fd| fd.write(YAML::dump(@configuration)) }
    open(@@FN_SETTINGS, "wb") { |fd| fd.write(YAML::dump(@settings)) }
  end

  # Load layout 
  def load_layout(fname)
  end

  def save_layout(fname)
  end

  def run
    # Launch application
    load_settings
    @appwindow = EmbracerWindow.new(@app)
    @app.create
    super
  end
end


# shortcut for the Embracer App
def appEM
  EmbracerApp.instance
end

# Shortcut for the FOX App
def appFX
  appEM.app
end

# Shortcut to get to the MongoDB
def appDB
  appEM.db
end

# Mixin for Windows and Dialogs
module BaseFunctionality
  include EOStruct

  FWIDTH = 8

  def newLabel(p, text, *rest)
    FXLabel.new(p, text, *rehash(*rest, :opts => JUSTIFY_RIGHT))
  end

  def newIconLabel(p, text, icon, *rest)
    FXLabel.new(p, text, icon, *rehash(*rest, :opts => JUSTIFY_RIGHT))
  end

  # display-only
  def newTextDisplay(p, *rest)
    FXTextField.new(p, FWIDTH, *rehash(*rest, 
                                   :opts => JUSTIFY_LEFT | FRAME_LINE | TEXTFIELD_READONLY,
                                   :selector => FXDataTarget::ID_VALUE))
  end

  # display-only
  def newNumericDisplay(p, *rest)
    FXTextField.new(p, FWIDTH, *rehash(*rest, 
                                   :opts => JUSTIFY_LEFT | FRAME_LINE | TEXTFIELD_READONLY | TEXTFIELD_REAL,
                                   :selector => FXDataTarget::ID_VALUE))
  end

  def newIntegerDisplay(p, *rest)
    FXTextField.new(p, FWIDTH, *rehash(*rest, 
                                   :opts => JUSTIFY_LEFT | FRAME_LINE | TEXTFIELD_READONLY | TEXTFIELD_INTEGER,
                                   :selector => FXDataTarget::ID_VALUE))
  end


  def newTextDesc(p, *rest, &block)
    FXText.new(p, *rehash(*rest, 
                          :selector => FXDataTarget::ID_VALUE,
                          :opts => JUSTIFY_LEFT | FRAME_LINE | HSCROLLING_OFF \
                          | TEXT_WORDWRAP | TEXT_READONLY|LAYOUT_FILL
                          ), &block)
  end

  def newTextLog(p, *rest, &block)
    FXText.new(p, *rehash(*rest, 
                          :opts => JUSTIFY_LEFT | FRAME_LINE | HSCROLLING_OFF \
                          | TEXT_WORDWRAP | TEXT_READONLY | LAYOUT_FILL | TEXT_AUTOSCROLL,
                          :selector => FXDataTarget::ID_VALUE
                          ), &block)
  end

  def newTextField(p, *rest)
    FXTextField.new(p, FWIDTH, *rehash(*rest, :selector => FXDataTarget::ID_VALUE))
  end

  def newPasswordField(p, *rest)
    FXTextField.new(p, 8, 
                    *rehash(*rest, 
                            :opts => TEXTFIELD_PASSWD|TEXTFIELD_NORMAL,
                            :selector => FXDataTarget::ID_VALUE))
  end


  def newNumberField(p, *rest)
    FXTextField.new(p, FWIDTH, 
                    *rehash(*rest, 
                            :opts => TEXTFIELD_REAL|TEXTFIELD_NORMAL,
                            :selector => FXDataTarget::ID_VALUE))
  end

  def newIntegerField(p, *rest)
    FXTextField.new(p, FWIDTH, 
                    *rehash(*rest, 
                            :opts => TEXTFIELD_INTEGER|TEXTFIELD_NORMAL,
                            :selector => FXDataTarget::ID_VALUE))
  end
  
  def newButton(p, label, *rest)
    FXButton.new(p, label, 
                 *rehash(*rest, 
                         :opts => ICON_ABOVE_TEXT \
                         | FRAME_RAISED \
                         | FRAME_THICK \
                         | JUSTIFY_NORMAL \
                         | LAYOUT_FILL_ROW))
  end


  def newListBox(p, *rest, &block)
    FXListBox.new(p, *rehash(*rest, 
                             :opts => LAYOUT_FILL_X|FRAME_SUNKEN,
                             :selector => FXDataTarget::ID_VALUE), &block)
  end

  def newCheck(p, text, *rest)
    FXCheckButton.new(p, text, 
                      *rehash(*rest, 
                              :opts => CHECKBUTTON_NORMAL,
                              :selector => FXDataTarget::ID_VALUE))
  end

  def newHF(p = @mf, *rest)
    FXHorizontalFrame.new(p, *rehash(*rest, :opts => LAYOUT_FILL_X|FRAME_SUNKEN))
  end

  def newHFFlat(p = @mf, *rest)
    FXHorizontalFrame.new(p, *rehash(*rest, :opts => LAYOUT_FILL_X))
  end

  def newVF(p = @mf, *rest)
    FXVerticalFrame.new(p, *rehash(*rest, :opts => LAYOUT_FILL_Y|FRAME_SUNKEN))
  end

  def newBidAsk(p = @mf, *rest)
    EMBidAskSizer.new(p, *rehash(*rest, :opts => LAYOUT_FILL_X|LAYOUT_FILL_Y|FRAME_RAISED,
                                 width: 20,
                                 height: 10))
  end

  def newVFFlat(p = @mf, *rest)
    FXVerticalFrame.new(p, *rehash(*rest, :opts => LAYOUT_FILL_X))
  end

  def newSwitcher(p = @mf, *rest)
    FXSwitcher.new(p, *rehash(*rest, :opts => LAYOUT_FILL|FRAME_SUNKEN))
  end

  def newHFButtons(*all)
    FXHorizontalFrame.new(@mf, 
                          *rehash(*all, :opts => LAYOUT_FILL_X \
                                  | FRAME_SUNKEN \
                                  | PACK_UNIFORM_WIDTH \
                                  | PACK_UNIFORM_HEIGHT))
  end

  def newVSep(*all)
    FXHorizontalSeparator.new(@mf, 
                              *rehash(*all,
                                      :opts => LAYOUT_FILL_X, 
                                      :padTop => 2, 
                                      :padBottom => 1))
  end

  def newHSep(p, *rest)
    FXVerticalSeparator.new(p, 
                            *rehash(*rest,
                                    :opts => LAYOUT_FILL_Y | SEPARATOR_GROOVE, 
                                    :padLeft => 5, 
                                    :padRight => 5))
  end

  def newRowMatrix(p, n, *rest)
    FXMatrix.new(p, n, *rehash(*rest,
                               :opts => MATRIX_BY_ROWS \
                               | PACK_UNIFORM_WIDTH \
                               | PACK_UNIFORM_HEIGHT))
  end

  def newColMatrix(p, n, *rest)
    FXMatrix.new(p, n, *rehash(*rest,
                               :opts => MATRIX_BY_COLUMNS \
                               | PACK_UNIFORM_WIDTH \
                               | PACK_UNIFORM_HEIGHT))
  end

end


# Base child window class for Embracer.
# Has facilities for automatically adding a menu entry.
class EMChild < FXMDIChild
  include DRb::DRbUndumped
  include BaseFunctionality

  # Add yourself by adding the entry << ["Menu Item Text", "Window Name", self]
  @@MENU = []
  
  # Menu list to add to the "Operations" menu.
  def self.menuList; @@MENU ; end
end

# Base custom dialog class
class EMDialogBox < FXDialogBox
  include DRb::DRbUndumped
  include BaseFunctionality

  def initialize(title)
    super(appFX, title)
  end

  def execute
    create
    super
  end
end

class LoginDialog < EMDialogBox
  attr_accessor :info

  def initialize(header = "Login", &block)
    super(header)
    @loginCode = block

    # Data
    @info = {
      :username => FXDataTarget.new(""), 
      :password => FXDataTarget.new("")
    }

    # GUI
    @mf = FXMatrix.new(self, 2,
                       :opts => LAYOUT_FILL \
                       | FRAME_RAISED \
                       | MATRIX_BY_COLUMNS \
                       | PACK_UNIFORM_WIDTH)
    newLabel(@mf, "Username")
    @userField = newTextField(@mf, :target => @info[:username])
    newLabel(@mf, "Password")
    @passwordField = newPasswordField(@mf, :target => @info[:password])

    (@okButton = newButton(@mf, "OK", :target => self, :selector => ID_ACCEPT))
    (@cancelButton = newButton(@mf, "CANCEL", :target => self, :selector => ID_CANCEL))
  end

  def execute
    @loginCode.call(@info[:username].to_s, @info[:password].to_s) unless super == 0
  end
end



# Position
class PositionWindow < EMChild
  @@MENU << ["Position", "Position", self]

  @@COLUMNS = [[:symbol, "Symbol"], 
               [:type, "Long/Short"],
               [:contracts, "Contracts"],
               [:strike, "Strike"],
               [:last, "Last"],
               [:bid, "Bid"],
               [:ask, "Ask"],               
               [:profit, "P/L"], 
               [:watcher, "Watcher"],
               [:message, "Message"]]

  def initialize(*args)
    super(*args)
    @tablew = FXTable.new(FXScrollWindow.new(self, 0), 
                          :opts => TABLE_COL_SIZABLE | TABLE_NO_COLSELECT | TABLE_READONLY \
                          | LAYOUT_FILL_X | LAYOUT_FILL_Y) { |tw|
      tw.appendColumns(@@COLUMNS.length)
      @@COLUMNS.each_with_index { |(sym, label), i|
        tw.setColumnText(i, label)
      }
      tw.horizontalGridShown = tw.verticalGridShown = true
    }
    @ptarget = appEM.broker.getPositions { |apos|
      apos.each_with_index { |po, row|
        @tablew.appendRows() if @tablew.numRows < row+1
        @@COLUMNS.each_with_index { |(sym, label), col|
          @tablew.setItemText(row, col, po._hash[sym].to_s) if po._hash.has_key? sym
          puts "#{row},#{col}[#{sym}] -> #{po._hash[sym]}" if po._hash.has_key? sym          
        }
      }
      if apos.length < @tablew.numRows
        @tablew.removeRows(apos.length, @table.numRows - apos.length)
      end
    }
  end
end


# Activity
class ActivityWindow < EMChild
  @@MENU << ["Activity", "Activity (dynamic)", self]

  @@COLUMNS = [
               [:message, "Message"],
               [:TransID, "Trans#"],
               [:TotalCost, "TC"],
               [:symbol, "Symbol"], 
               [:type, "Long/Short"],
               [:contracts, "Contracts"],
               [:strike, "Strike"],
               [:last, "Last"],
               [:bid, "Bid"],
               [:ask, "Ask"],               
               [:profit, "P/L"], 
               [:watcher, "Watcher"],
              ]

  # seconds in one day
  DAY = 3600 * 24
  WEEK = DAY * 7
  MONTH = DAY * 30
  YEAR = DAY * 365 

  def initialize(*args)
    super(*args)
    @tablew = FXTable.new(FXScrollWindow.new(self, 0), 
                          :opts => TABLE_COL_SIZABLE | TABLE_NO_COLSELECT | TABLE_READONLY \
                          | LAYOUT_FILL_X | LAYOUT_FILL_Y) { |tw|
      tw.appendColumns(@@COLUMNS.length)
      @@COLUMNS.each_with_index { |(sym, label), i|
        tw.setColumnText(i, label)
      }
      tw.horizontalGridShown = tw.verticalGridShown = true
    }
    # we wish to pull a whole year of activity.
    endTime = Time.new
    startTime = endTime - YEAR
    @ptarget = appEM.broker.getActivity(startTime, nil) { |aact|
      aact.each_with_index { |act, row|
        @tablew.appendRows() if @tablew.numRows < row+1
        @@COLUMNS.each_with_index { |(sym, label), col|
          @tablew.setItemText(row, col, act._hash[sym].to_s) if act._hash.has_key? sym
        }
      }
      if aact.length < @tablew.numRows
        @tablew.removeRows(aact.length, @table.numRows - aact.length)
      end
    }
  end
end


# Order Status
class OrderStatusWindow < EMChild
  @@MENU << ["Order Status", "Order Status (dynamic)", self]

  @@COLUMNS = [
               [:orderID, "ID"],
               [:iDate, "Date"],
               [:iTime, "Time"],
               [:symbol, "Symbol"], 
               [:description, "Desc"],
               [:type, "Long/Short"],
               [:status, "Status"],
               [:contracts, "Contracts"],
               [:limit, "Limit"],
               [:stop, "Stop"],
               [:strike, "Strike"],
               [:watcher, "Watcher"],
               [:fDate, "Fill Date"],
               [:fTime, "Fill Time"],
              ]

  def initialize(*args)
    super(*args)
    @tablew = FXTable.new(FXScrollWindow.new(self, 0), 
                          :opts => TABLE_COL_SIZABLE | TABLE_NO_COLSELECT | TABLE_READONLY \
                          | LAYOUT_FILL_X | LAYOUT_FILL_Y) { |tw|
      tw.appendColumns(@@COLUMNS.length)
      @@COLUMNS.each_with_index { |(sym, label), i|
        tw.setColumnText(i, label)
      }
      tw.horizontalGridShown = tw.verticalGridShown = true
    }
    @ptarget = appEM.broker.getOrderStatus(nil, 100) { |ost|
      ost.each_with_index { |os, row|
        @tablew.appendRows() if @tablew.numRows < row+1
        @@COLUMNS.each_with_index { |(sym, label), col|
          @tablew.setItemText(row, col, os._hash[sym].to_s) if os._hash.has_key? sym
        }
      }
      if ost.length < @tablew.numRows
        @tablew.removeRows(ost.length, @table.numRows - ost.length)
      end
    }
  end
end



# Monitors status updates from OptionsXpress.
class MonitorWindow < EMChild
  @@MENU << ["Monitor", "Monitor", self]

  def initialize(*args)
    super(*args)
    @listw = FXList.new(FXScrollWindow.new(self, 0), 
                       :opts => LIST_SINGLESELECT | LAYOUT_FILL_X | LAYOUT_FILL_Y
                       ) { |lw|
      lw.appendItem("Monitor Started.")
    }

    appEM.broker.register(:broker_log) { |type, note| @listw.appendItem(note) }
  end
end


#= Trader Window
# This is a rather complicated beastie, but is the main focus of all this after all.
class TraderWindow < EMChild
  include Bells

  @@MENU << ["Trader", "Trader", self]

  include Follower

  @@WATCHERS = [
                [Follower, "The Follower", "Basic Trailing Stop Management"],
               ]

  @@buyIcon        = FXPNGIcon.new(appFX, File.open("icons/buy.png" , "rb" ).read)
  @@shortIcon      = FXPNGIcon.new(appFX, File.open("icons/short.png" , "rb" ).read)
  @@flatIcon       = FXPNGIcon.new(appFX, File.open("icons/flat.png" , "rb" ).read)
  @@flipIcon       = FXPNGIcon.new(appFX, File.open("icons/flip.png" , "rb" ).read) 
  @@panicIcon      = FXPNGIcon.new(appFX, File.open("icons/panic.png" , "rb" ).read) 
  @@bullIcon       = FXPNGIcon.new(appFX, File.open("icons/bull.png" , "rb" ).read) 
  @@bearIcon       = FXPNGIcon.new(appFX, File.open("icons/bear.png" , "rb" ).read) 
  @@notInTradeIcon = FXPNGIcon.new(appFX, File.open("icons/not_in_trade.png" , "rb" ).read) 

  @@LORS = {
    long: @@bullIcon,
    short: @@bearIcon,
    nit: @@notInTradeIcon,
  }

  # Color format is BGR!!!
  COLOR_RED     = 0x0000FF
  COLOR_GREEN   = 0x00FF00
  COLOR_WHITE   = 0xFFFFFF
  # For StatusBar
  COLOR_ARMED   = 0x4488FF
  COLOR_UNARMED = 0xC8D0D4
  COLOR_FAILED  = COLOR_RED

  def color?(pl)
    if pl > 0 
      COLOR_GREEN
    elsif pl < 0
      COLOR_RED
    else
      COLOR_WHITE
    end  
  end


  def initialize(*args)
    super(*args)
    @lambda_quote_update = nil # To anchor this lamnda from GC!!!

    ## Watcher Initialzation
    @watchers = []
    @@WATCHERS.each { |wclass, wname, wdesc|
      @watchers << [wclass.new, wname, wdesc]
    }

    # Since there is only one watcher at the moment, just set it as the default. FIX!!!!
    @watcher = @watchers[0][0] #FIX!!! Temporary

    @mf = FXVerticalFrame.new(self, :opts => LAYOUT_FILL | FRAME_RAISED)

    ## Futures Symbols and quantities
    # Data Targets
    @last_future = "ES #F" # so we know what to unregister.
    @future_block = nil # block used to register future symbol

    (@dt_future = FXDataTarget.new("ES #F")).connect(SEL_CHANGED, method(:onCmdFuture))
    (@dt_future_broker = FXDataTarget.new("ES/10U")).connect(SEL_CHANGED, method(:onCmdFuture))
    (@dt_quantity = FXDataTarget.new(1)).connect(SEL_CHANGED, method(:onCmdQuantity))

    # Wigets
    vf = newVFFlat
    hf = newHF vf
    newLabel(hf, "Future")
    @w_future = newTextField(hf, target: @dt_future)
    newLabel(hf, "Future (Broker)")
    @w_future_broker = newTextField(hf, target: @dt_future_broker)
    newLabel(hf, "Quantity")
    @w_quantity = newNumberField(hf, target: @dt_quantity)
    
    # Widgets generated from the Watcher selection
    @f_watcher_switcher = newSwitcher vf
    generate_watcher_widgets

    newVSep

    ## Futures Symbol Quotes
    # data targets
    @dt_bid = FXDataTarget.new(0.0)
    @dt_ask = FXDataTarget.new(0.0)
    @dt_last = FXDataTarget.new(0.0)
    @dt_bidsize = FXDataTarget.new(0)
    @dt_asksize = FXDataTarget.new(0)
    @dt_traded = FXDataTarget.new(0)
    @dt_datetime = FXDataTarget.new("")
    
    # Widgets
    hf = newHF
    newLabel(hf, "Bid")
    @w_bidQ  = newNumericDisplay(hf, target: @dt_bid)
    newLabel(hf, "Ask")
    @w_askQ = newNumericDisplay(hf, target: @dt_ask)
    newLabel(hf, "Last")
    @w_lastQ = newNumericDisplay(hf, target: @dt_last)
    newHSep(hf)
    # newLabel(hf, "Bid Size")
    # @w_bidSizeQ  = newIntegerDisplay(hf, target: @dt_bidsize)
    # newLabel(hf, "Ask Size")
    # newHSep(hf)
    # @w_askSizeQ  = newIntegerDisplay(hf, target: @dt_asksize)
    # newLabel(hf, "Traded")
    # @w_tradedQ  = newIntegerDisplay(hf, target: @dt_traded)
    # newLabel(hf, "Time")
    # @w_datetime  = newTextDisplay(hf, target: @dt_datetime)
    @w_bidAsk = newBidAsk(hf)

    ## Trade Execution
    # data targets
    @dt_watcher = FXDataTarget.new(0)
    @dt_watcher_status = FXDataTarget.new("Description?")
    @dt_arm_switch = FXDataTarget.new(FALSE)

    # widgets -- Watcher Management
    newVSep
    hf = newHFButtons
    vf = newVF hf
    @watcherLB = newListBox(vf, target: @dt_watcher) { |lb|
      @watchers.each { |watcher, wname, wdesc|
        lb.appendItem(wname)
      }
    }
    @w_watcher_status = newTextDesc(vf, target: @dt_watcher_status)
    @w_watcher_status.font = appEM.smallFont
    @dt_watcher_status.value = @watcher.desc # FIX!!! Need to change when watcher is changed.
    (@w_arm_switch = newCheck(vf, "Armed?", 
                             target: @dt_arm_switch)).connect(SEL_COMMAND, method(:onArmSwitch))

    # widgets -- Execution
    mx = newRowMatrix(hf, 2)
    @bctrl = {} 
    (@bctrl[:buy] = @w_buy = newButton(mx, "&Buy", @@buyIcon)).connect(SEL_COMMAND, method(:onCmdBuy))
    (@bctrl[:short] = @w_short = newButton(mx, "&Short", @@shortIcon)).connect(SEL_COMMAND, method(:onCmdShort))
    (@bctrl[:flat] = @w_flat = newButton(mx, "Go &Flat", @@flatIcon)).connect(SEL_COMMAND, method(:onCmdFlat))
    (@bctrl[:flip] = @w_flip = newButton(mx, "&Reverse", @@flipIcon)).connect(SEL_COMMAND, method(:onCmdReverse))
    (@bctrl[:panic] = @w_panic = newButton(mx, "&Panic", @@panicIcon)).connect(SEL_COMMAND, method(:onCmdPanic))

    # Long/Short Indicator
    @w_lors = newIconLabel(hf, "", @@notInTradeIcon,
                       :opts => JUSTIFY_CENTER_X \
                       | ICON_ABOVE_TEXT \
                       | LAYOUT_FILL_Y)

    ## Profit Tracker
    # data targets
    @dt_pointPL = FXDataTarget.new(0.0)
    @dt_tradePL = FXDataTarget.new(0.0)
    @dt_totalPL = FXDataTarget.new(0.0)
    @dt_balance = FXDataTarget.new(0.0)
    @dt_timeInTrade = FXDataTarget.new("00:00:00")

    # widgets
    newVSep
    hf = newHF
    newLabel(hf, "Point P/L")
    @w_pointPL = newNumericDisplay(hf, target: @dt_pointPL)
    newHSep(hf)
    newLabel(hf, "Trade P/L")
    @w_tradePL = newNumericDisplay(hf, target: @dt_tradePL)
    newHSep(hf)
    newLabel(hf, "Total P/L")
    @w_totalPL = newNumericDisplay(hf, target: @dt_totalPL)
    newHSep(hf)
    newLabel(hf, "Balance")
    @w_balance = newNumericDisplay(hf, target: @dt_balance)
    newHSep(hf)
    newLabel(hf, "TnT")
    @w_timeInTrade = newTextDisplay(hf, target: @dt_timeInTrade)

    ## Activity
    # data target
    @dt_log = FXDataTarget.new("Log of avtivities\n\n")
    # widgets
    newVSep
    @w_log = newTextLog(@mf, target: @dt_log)

    ## Status Bar
    @statusBar = FXStatusBar.new(@mf, LAYOUT_SIDE_BOTTOM| LAYOUT_FILL_X)

    ## Set the default width and height
    resize(920, 500)
    move(10,10)

    ## Get stuff going!
    loadDefaults
    registerSymbol(@dt_future.to_s)
    @watcher.fregister(:status, :update) { |mstr|
      @dt_log.value = mstr + "\n" + @dt_log.value
      puts "SU: #{Time.now}: #{mstr}" if $verbose or $debug
    }

    @watcher.fregister(:state, :transition) { |state, contracts, *rest|
      (state, @statusBar.statusLine.normalText) = @watcher.state_info
      ts = Time.now.strftime("%F %H:%M:%S")
      sstr = "#{ts} >>TR: #{state} -> #{rest}"
      @dt_log.value =  sstr + "\n" + @dt_log.value
      puts "ST: #{Time.now}: #{sstr}" if $verbose or $debug
      case state
      when :dormant
        bctrl :flat, :flip, :panic
      when :bug, :dead, :failed
        bctrl :flat, :flip, :buy, :short, :panic
        @statusBar.statusLine.backColor = COLOR_FAILED if armed?
        bell_error
      when :hot
        bctrl :buy, :short, :panic
        lors_status(if contracts > 0
                      :long
                    else
                      :short
                    end)
      when :reversal
        bctrl 
      when :flat
        bctrl :buy, :short, :flat, :flip, :panic
        lors_status :nit
      end
    }

    @watcher.fregister(:profit, :update) { |pointPL, tradePL, totalPL, balance, timeInTrade|
      @dt_pointPL.value = sprintf "%7.2f", pointPL
      @dt_tradePL.value = sprintf "$%7.2f", tradePL
      @dt_totalPL.value = sprintf "$%7.2f", totalPL
      @dt_balance.value = sprintf "$%7.2f", balance
      @dt_timeInTrade.value = timeInTrade

      @w_pointPL.backColor = color? pointPL
      @w_tradePL.backColor = color? tradePL
      @w_totalPL.backColor = color? totalPL 
    }
    @watcher.ping # force an initial update of status.
    bctrl :flat, :flip, :panic # disable these buttions initially.
  end

  # Load defaults for this class
  def loadDefaults
    appDB[:defaults].find(:name => self.class.to_s) { |cur|
      cur.each { | doc |
        unless doc.nil?
          @defaults = doc.to_eos

          # Future symbols
          @dt_future.value = @defaults.future.datafeed
          @dt_future_broker.value = @defaults.future.broker
          @dt_quantity.value = @defaults.future.quantity unless @defaults.future.quantity.nil?

          # Watcher Widgets
          @defaults.watchers._hash.each_pair{ |wclazz, dw|
            @dtw_all_watchers.each { |w, g|
              p w.class.to_s
              if w.class.to_s == wclazz.to_s
                dw._hash.each_pair { |sym, val|
                  @dtw_all_watchers[w][:dt][sym.to_sym].value = val
                }
              end
            }
          }
        end
      }
    }
  end

  # Save defaults for this class.
  def saveDefaults
    if @defaults.nil?
      @defaults = create_eos
      @defaults.name = self.class.to_s
    end
    # Futures symbols
    @defaults.future = create_eos
    @defaults.future.datafeed = @dt_future.value
    @defaults.future.broker = @dt_future_broker.value
    @defaults.future.quantity = @dt_quantity.value
    
    # Watcher Widgets
    @defaults.watchers = create_eos
    @watchers.each { |w, wname, wdesc|
      dw = @defaults.watchers._hash[w.class.to_s] = create_eos
      @dtw_all_watchers[w][:dt].each_pair { |sym, dt|
        dw._hash[sym] = dt.value
      }
    }
    appDB[:defaults].save(@defaults.to_doc)
  end
  

  # Long/Short Indicator 
  # :long, :short, :nit (not in trade)
  def lors_status(status)
    @@LORS[status].create
    @w_lors.icon = @@LORS[status]
  end

  # Button Control
  #
  # Just pass in a list of buttons to disable (see the @bctrl map), and
  # the rest not mentioned will be enabled.
  def bctrl(*list)
    @bctrl.each { |b, w|
      if list.member? b
        w.disable
      else
        w.enable
      end
    }
  end  

  # Generate all the Watcher widgets for all Watchers listed.
  #
  # These widget groups shall be placed in an FXSwitcher window heirarchy.
  #
  # @f_watcher_switch contains the master layout window.
  def generate_watcher_widgets
    @dtw_all_watchers = {}
    @watchers.each { | w, wname, wdesc |
      @dtw_all_watchers[w] = g = {}
      g[:dt] = dtw = {}
      g[:widget] = wid = {}
      hf = newHFFlat @f_watcher_switcher
      w.fields.each { |sym, type, default, name, desc|
        dtw[sym] = FXDataTarget.new(default)
        wid[sym] = case type
                   when :bool
                     newLabel(hf, name)
                     newCheck(hf, '', target: dtw[sym])
                   when :int
                     newLabel(hf, name)
                     newIntegerField(hf, target: dtw[sym])
                   when :float
                     newLabel(hf, name)
                     newNumberField(hf, target: dtw[sym])
                   when :string
                     newLabel(hf, name)
                     newTextField(hf, target: dtw[sym])
                   end 
      }
    }
  end

  def watcher_parms
    p ={}
    @dtw_all_watchers[@watcher][:dt].each_pair { |sym, dt|
      p[sym] = dt.value
    }
    p
  end

  def armed?
    @w_arm_switch.checked?
  end

  def onArmSwitch(sender, sel, ptr)
    if @w_arm_switch.checked?
      @watcher.armed = FXMessageBox.warning(self, 
                                            MBOX_OK_CANCEL, 
                                            "Arming for LIVE TRADING", 
                                            "Are you sure you want to arm for LIVE TRADING?"
                                            ) == MBOX_CLICKED_OK
      # Do some more arming stuff
      @w_arm_switch.setCheck(@watcher.armed, true)
      @statusBar.statusLine.backColor = COLOR_ARMED
      bell_armed
    else
      @w_arm_switch.setCheck(@watcher.armed = false, true)
      # Do disarming stuff
      @statusBar.statusLine.backColor = COLOR_UNARMED
      bell_unarmed
    end
  end
  
  # User typed in new future symbol
  def onCmdFuture(sender, sel, ptr)
    registerSymbol(@dt_future.to_s)
  end

  def onCmdQuantity(sender, sel, ptr)
  end

  def onCmdTick(sender, sel, ptr)
  end

  # Command to BUY
  def onCmdBuy(sender, sel, ptr)
    saveDefaults # FIX!!! Is this the best place for this????
    bctrl :buy, :short, :flip, :flat
    @watcher.cmdBuy(@dt_future.to_s,
                    @dt_future_broker.to_s,
                    @dt_quantity.to_s.to_i, 
                    *watcher_parms)
  end

  # Command to SHORT
  def onCmdShort(sender, sel, ptr)
    saveDefaults # FIX!!! Is this the best place for this????
    bctrl :buy, :short, :flip, :flat
    @w_short.disable
    @w_buy.disable
    @watcher.cmdSellShort(@dt_future.to_s, 
                          @dt_future_broker.to_s,
                          @dt_quantity.to_s.to_i, 
                          *watcher_parms)
  end

  # Command to GO FLAT
  def onCmdFlat(sender, sel, ptr)
    bctrl :flat, :buy, :short, :flip
    @watcher.cmdGoFlat
  end

  # Command to GO HALF FLAT
  def onCmdHalfFlat(sender, sel, ptr)
    @watcher.cmdGoHalfFlat
  end

  # Command to Reverse position (long to short or short  to long)
  def onCmdReverse(sender, sel, ptr)
    bctrl :flat, :buy, :short, :flip
    @watcher.cmdReverse
  end

  # Kill all pending orders!
  def onCmdPanic(sender, sel, ptr)
    bctrl :flat, :buy, :short, :flip, :panic
    @watcher.cmdPanic
  end

  def registerSymbol(sym)
    puts "registering #{sym}"
    # unregister the last symbol
    appEM.quotes.unregisterQuotes(@last_future, @future_block) unless @future_block.nil?
    @last_future = sym
    @lambda_quote_update = lambda { |q|
      @w_bidAsk.updateQuote(q)
      @dt_bid.value  = sprintf "%8.2f", q.bid
      @dt_ask.value  = sprintf "%8.2f", q.ask
      @dt_last.value = sprintf "%8.2f", q.last
      @dt_bidsize.value = sprintf "%5d", q.bidSize
      @dt_asksize.value = sprintf "%5d", q.askSize
      @dt_traded.value = sprintf "%5d", q.tradeSize
      @dt_datetime.value = q.dateTime
    } if @lambda_quote_update.nil?
    @future_block = appEM.quotes.registerQuotes(sym, &@lambda_quote_update)
  end
end


class EmbracerWindow  < FXMainWindow
  @@statusBarIcon  = FXPNGIcon.new(appFX, File.open("icons/statusBarIcon.png" , "rb" ).read)

  (@@conGoodIcon = FXPNGIcon.new(appFX, File.open("icons/conGoodIcon.png" , "rb" ).read)).create
  (@@conPendingIcon = FXPNGIcon.new(appFX, File.open("icons/conPendingIcon.png" , "rb" ).read)).create
  (@@conBadIcon = FXPNGIcon.new(appFX, File.open("icons/conBadIcon.png" , "rb" ).read)).create

  (@@trProfitIcon = FXPNGIcon.new(appFX, File.open("icons/trProfitIcon.png" , "rb" ).read)).create
  (@@trLossIcon  = FXPNGIcon.new(appFX, File.open("icons/trLossIcon.png" , "rb" ).read)).create
  (@@trFlatIcon  = FXPNGIcon.new(appFX, File.open("icons/trFlatIcon.png" , "rb" ).read)).create

  def initialize(app)
    # Invoke base class initialize method first
    super(app, "The Embracer", :opts => DECOR_ALL, :width => 950, :height => 750)

    # Create the font
    @font = FXFont.new(appFX, "courier", 10, FONTWEIGHT_BOLD)
  
    # Menubar
    menubar = FXMenuBar.new(self, LAYOUT_SIDE_TOP|LAYOUT_FILL_X)
  
    # Status Bar
    @statusBar = FXStatusBar.new(self, 
                                 LAYOUT_SIDE_BOTTOM| LAYOUT_FILL_X | STATUSBAR_WITH_DRAGCORNER)

    # The good old penguin, what would we be without it?
    @tradeStatusButton = FXButton.new(@statusBar, "TR",
                                      :icon => @@trFlatIcon, 
                                      :opts => LAYOUT_RIGHT|TEXT_BEFORE_ICON)
    @connectionStatusButtonBroker = FXButton.new(@statusBar, "BR",
                                           :icon => @@conBadIcon, 
                                           :opts => LAYOUT_RIGHT|TEXT_BEFORE_ICON)
    @connectionStatusButtonFeed = FXButton.new(@statusBar, "DF",
                                           :icon => @@conBadIcon, 
                                           :opts => LAYOUT_RIGHT|TEXT_BEFORE_ICON)
 
    # MDI Client
    @mdiclient = FXMDIClient.new(self, LAYOUT_FILL_X|LAYOUT_FILL_Y)
  
    # Icon for MDI Child
    @mdiicon = nil
    File.open(File.join("icons", "embracer.png"), "rb") do |f|
      @mdiicon = FXPNGIcon.new(appFX(), f.read)
    end

    # Make MDI Menu
    @mdimenu = FXMDIMenu.new(self, @mdiclient)
 
    # MDI buttons in menu:- note the message ID's!!!!!
    # Normally, MDI commands are simply sensitized or desensitized;
    # Under the menubar, however, they're hidden if the MDI Client is
    # not maximized.  To do this, they must have different ID's.
    FXMDIWindowButton.new(menubar, @mdimenu, @mdiclient, FXMDIClient::ID_MDI_MENUWINDOW,
      LAYOUT_LEFT)
    FXMDIDeleteButton.new(menubar, @mdiclient, FXMDIClient::ID_MDI_MENUCLOSE,
      FRAME_RAISED|LAYOUT_RIGHT)
    FXMDIRestoreButton.new(menubar, @mdiclient, FXMDIClient::ID_MDI_MENURESTORE,
      FRAME_RAISED|LAYOUT_RIGHT)
    FXMDIMinimizeButton.new(menubar, @mdiclient,
      FXMDIClient::ID_MDI_MENUMINIMIZE, FRAME_RAISED|LAYOUT_RIGHT)
  
    # File menu
    filemenu = FXMenuPane.new(self)
    newCmd = FXMenuCommand.new(filemenu, "&New\tCtl-N\tCreate new document.")
    # newCmd.connect(SEL_COMMAND, method(:onCmdNew))

    FXMenuCommand.new(filemenu, "&Quit\tCtl-Q\tQuit application.", nil,
      appFX, FXApp::ID_QUIT, 0)
    FXMenuCommand.new(filemenu, "Broker Login").connect(SEL_COMMAND, method(:onCmdLoginBroker))
    FXMenuCommand.new(filemenu, "Datafeed Login").connect(SEL_COMMAND, method(:onCmdLoginDatafeed))

    FXMenuTitle.new(menubar, "&File", nil, filemenu)

    # Operations
    opmenu = FXMenuPane.new(self)
    EMChild.menuList.each { |menu_name, window_name, wclazz|
      FXMenuCommand.new(opmenu, menu_name).connect(SEL_COMMAND) { |sender, sel, ptr|
        w = wclazz.new(@mdiclient, window_name, @mdiicon, @mdimenu,
                       0, 100, 100, 500, 300)
        w.create
        w.raiseWindow
        w.setFocus
        @mdiclient.setActiveChild(w)
      }
    }
    FXMenuTitle.new(menubar, "Operations", nil, opmenu)

    # Window menu
    windowmenu = FXMenuPane.new(self)
    FXMenuCommand.new(windowmenu, "Tile &Horizontally", nil,
      @mdiclient, FXMDIClient::ID_MDI_TILEHORIZONTAL)
    FXMenuCommand.new(windowmenu, "Tile &Vertically", nil,
      @mdiclient, FXMDIClient::ID_MDI_TILEVERTICAL)
    FXMenuCommand.new(windowmenu, "C&ascade", nil,
      @mdiclient, FXMDIClient::ID_MDI_CASCADE)
    FXMenuCommand.new(windowmenu, "&Close", nil,
      @mdiclient, FXMDIClient::ID_MDI_CLOSE)
    sep1 = FXMenuSeparator.new(windowmenu)
    sep1.setTarget(@mdiclient)
    sep1.setSelector(FXMDIClient::ID_MDI_ANY)
    FXMenuCommand.new(windowmenu, nil, nil, @mdiclient, FXMDIClient::ID_MDI_1)
    FXMenuCommand.new(windowmenu, nil, nil, @mdiclient, FXMDIClient::ID_MDI_2)
    FXMenuCommand.new(windowmenu, nil, nil, @mdiclient, FXMDIClient::ID_MDI_3)
    FXMenuCommand.new(windowmenu, nil, nil, @mdiclient, FXMDIClient::ID_MDI_4)
    FXMenuCommand.new(windowmenu, "&Others...", nil, @mdiclient, FXMDIClient::ID_MDI_OVER_5)
    FXMenuTitle.new(menubar,"&Window", nil, windowmenu)
    
    # Help menu
    helpmenu = FXMenuPane.new(self)
    FXMenuCommand.new(helpmenu, "&About FOX...").connect(SEL_COMMAND) {
      FXMessageBox.information(self, MBOX_OK, "About MDI Test",
        "Test of the FOX MDI Widgets\nWritten by Jeroen van der Zijp")
    }
    FXMenuTitle.new(menubar, "&Help", nil, helpmenu, LAYOUT_RIGHT)

    # Add a timer to handle updating the status bar indicators
    # NOTE WELL: There can be only one timeout!
    appFX.addTimeout(250, method(:doGeneralUpdates), repeat: true)
  end

  # Update the status bar icons
  def doGeneralUpdates(sender, sel, data)
    # Connection
    @connectionStatusButtonBroker.icon = appEM.broker.loggedIn? ? @@conGoodIcon : @@conBadIcon
    @connectionStatusButtonFeed.icon = appEM.quotes.loggedIn? ? @@conGoodIcon : @@conBadIcon
    Funnel.process_funnel_messages(false)
  end

  # New
  def onCmdNew(sender, sel, ptr)
    mdichild = createTestWindow(20, 20, 300, 200)
    mdichild.create
    return 1
  end

  def onCmdLoginBroker(sender, sel, ptr)
    lg = LoginDialog.new("Broker Login") { |user, pass|
      begin
        appEM.broker.login(user, pass)
        appEM.credentials[:broker_user] = user
        appEM.credentials[:broker_pass] = pass
      rescue BrokerException => ex
        FXMessageBox.error(appFX, MBOX_OK, "Login to Broker Failed",  ex.to_s)
      end unless pass.nil? # new calls this up front, so check.
    }
    lg.execute
  end

  def onCmdLoginDatafeed(sender, sel, ptr)
    lg = LoginDialog.new("Datafeed Login") { |user, pass|
      begin
        appEM.quotes.login(user, pass)
        appEM.credentials[:datafeed_user] = user
        appEM.credentials[:datafeed_pass] = pass
      rescue DatafeedException => ex
        FXMessageBox.error(appFX, MBOX_OK, "Login to Datafeed Failed",  ex.to_s)
      end
    }
    lg.execute
  end

  # Start
  def create
    super

    # At the time the first three MDI windows are constructed, we don't
    # yet know the font height and so we cannot accurately set the line
    # height for the vertical scrollbar. Now that the real font has been
    # created, we can go back and fix the scrollbar line heights for these
    # windows.
    @font.create
    @mdiclient.each_child do |mdichild|
      mdichild.contentWindow.verticalScrollBar.setLine(@font.fontHeight)
    end

    show(PLACEMENT_SCREEN)
  end
end

# Launch application
if __FILE__ == $0
  $debug = true
  $warning = true
  $verbose = true
  $trap = false # let nothing go to the server!
  $logxml = true

  puts "DEBUG" if $debug
  puts "WARNING" if $warning
  puts "VERBOSE" if $verbose
  puts "TRAP" if  $trap
  puts "LOGXML" if $logxml
  EmbracerApp.instance.run
end
