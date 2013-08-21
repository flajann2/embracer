=begin rdoc
=Application -- Application Handler for FOX
The Application needs to be managed from a singular location. This would be the 
Application object. This integrates with FOX for launching the application,
handling persistence, and the like.
=end

require 'fox16'
require 'fox16/colors'
require 'singleton'
require 'mongo'

module Application
  include Fox

  class ApplicationException < Exception
  end

  # We'll simply get this class by doing an App.instance call
  class App < FXObject
    include Singleton

    def initialize
      @@APP = self
    end

    def run
      @app.run
    end

    # Complete dump of the application state (must be implemented by subclass)
    # Retuns a YAML dump of application state.
    def dump
      raise ApplicationException.new("Subclass must implement dump()")
    end

    # Complete load of application state (must be implemented by subclass)
    # Takes a YAML string of application state.
    def load(yamlState)
      raise ApplicationException.new("Subclass must implement load()")
    end

    # Main Application (ruby)
    def self.EM ; @@APP ; end

    # Main Application (FOX)
    def self.FX ; @@APP.app ; end

    # Mongo DB we're using throughout.
    def self.DB ; @@APP.db ; end
  end
end
