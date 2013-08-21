# Market base class for all market interfaces (Datafeeds and Brokers, etc,)
require 'fox16'

include Fox

=begin rdoc
=Market Foundational Classes (MarketFC)
=end
module MarketFC
  class MarketException < Exception
  end

  class Market < FXObject
    def initialize
      super
      # Login variables
      @username = @password = nil
      
      # notification message types -- reset these per your needs
      @log_mt = :log
      @gui_mt = :gui_update
    end
    
    ## Login 
    # Login when this is called. Basically, the
    # details of the login (username and password, etc.)
    # are stored in this instance.
    #
    # Override this function, and call the super for this in the
    # override to store the username and password.
    #
    # An exception is raised if this fails. That is, your override
    # shall raise it.
    #
    ## Postman Messages
    # :broker_log => :notice, text
    # :gui_update => :login, [:pending | :logout]
    def login(username = nil, password = nil)
      @username = username unless username.nil?
      @password = password unless password.nil?
      transmit(@log_mt, :notice, "User #{@username} attemped to log in.")
      transmit(@gui_mt, :login, :pending)
    end
    
    # Destroy login information
    def logout
      @username = @password = nil
      transmit(:qoute_log, :notice, "Logged out.")
      transmit(:gui_update, :login, :logout)
    end
    
    # This must be implemented in the subclassed Broker object.
    def loggedIn?
      raise MarketException.new("Method Not Implemented Yet.")
    end

    # This will normally create a new object, but could be overriden 
    # to do something different.
    def Market.create(*parms)
      new(*parms)
    end
  end
end
