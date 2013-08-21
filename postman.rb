=begin rdoc

= Postman -- simple messaging mixin

All objects that send and receive these messages should mixin the Postman module.

The Postman works in a simple manner. The class implementing the Postman will
mixin this module, and call transmit whenever it has messages to transmit. The
transmits will be sent to a symbol message type that can be listened to.

A listener will call register with the symbol message type he is interested in
receiving, and will pass to it a  callback function to receive the notifications.

As messages are transmitted, they will be sent to the callbacks. It is important
for the callbacks to return as soon as possible to keep everything flowing smoothly.
=end

require 'funnel'

module Postman
  class PostmanException < Exception; end

  # Call super from your initalizer to set this up.
  def initialize(*all)
    super(*all)
    @listeners ={}
  end
  
  # Get an array of message types.
  def types_of
    @listeners.keys.clone.freeze
  end

  # Get a array list of subtypes for a given message type
  def subtypes_of(message_type)
    unless @listeners[message_type].nil?
      @listeners[message_type].keys.clone.freeze
    else
      []
    end
  end

  # Remove any types and subtypes that don't have receivers!
  def purge_all
    @listeners.each { |type, subtypes|
      subtypes.each { |subtype, ar|
        subtypes.delete(subtype) if ar.nil? or ar.empty?
      }
      @listeners.delete(type) if subtypes.empty?
    }
  end

  def remove_type(message_type)
    @listeners.delete(message_type)
    purge_all
  end

  def remove_subtype(message_type, message_subtype)
    @listeners[message_type].delete(message_subtype) unless @listeners[message_type].nil?
    purge_all
  end

  # Register with a Funnel Wrapper on the listener.
  def fregister(message_type, message_subtype = nil, &listener)
    _register(message_type, message_subtype , Funnel.wrap(listener))
  end

  # register a message type and a block to call.
  # message_type is a symbol representing the message type.
  def register(message_type, message_subtype = nil, &listener)
    _register(message_type, message_subtype, listener)
  end
  
  #internal register (don't call directly)
  def _register(mtype, msubtype, listener)
    @listeners[mtype] = {} unless @listeners.has_key? mtype
    @listeners[mtype][msubtype] = [] unless @listeners[mtype].has_key? msubtype
    @listeners[mtype][msubtype].push(listener)
  end

  # transmit all the parameters to all the listeners of the particular message type.
  # A listener can remove itself by returning the :remove_me symbol.
  # A listener will be removed automatically if it tosses an exception.
  def transmit(message_type, message_subtype = nil, *parms)
    @listeners[message_type][message_subtype].each { |listener|
      begin
        if listener.(*parms) == :remove_me
          @listeners[message_type][message_subtype] -= [listener]
        end
      rescue
        p $!
        puts $!
        puts $!.backtrace.join("\n")
        @listeners[message_type][message_subtype] -= [listener] # remove offending listener
        purge_all
      end
    } unless @listeners[message_type].nil? or @listeners[message_type][message_subtype].nil?
  end
  
  # remove this listener from the list.
  def unregister(message_type, message_subtype = nil, &block)
    @listeners[message_type][message_subtype] -= [block] unless @listeners[message_type].nil? or @listeners[message_type][message_subtype].nil?
    purge_all
  end
end
