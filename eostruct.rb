=begin rdoc
=EOpenStruct -- Enhanced OpenStruct for use with Mongo and XML. $Rev: 1076 $

Embracer does a lot of interaction with XML, and soon with the MongoDB.
Since we use OpenStruct as the basis for data structers in Embracer,
we need clean interoperability with both XML and MongoDB.

MongoDB expects data structers to be in a nested Hash format, and
so we have that impedance mishmatch to deal with as well.

Communication to the data servers and brokers are in XML, for the most part,
and so that impedance mismatch exists as well

The Enhanced OpenStruct mixins takes care of these issues, and allow us to
just use OpenStruct everywhere.
=end

require 'ostruct'

=begin rdoc
=EOStruct -- Mixin 

This mixin is expected to be used in any arbitrary class to add functionality
for handling OpenStructs as a type of "Hash", though we could have implemented
this as a pure mixing for OpenStruct instead.

Ahh, but we have "legacy" code now. I may clean this up at a future date. FIX!!!
=end
module EOStruct
  class EOSException < Exception
  end

  # Mixin to extend OpenStruct.
  module EOS
    def deep_inspect ;  @table ; end

    # Convert nested OpenStruct objects to "document" form -- nested hashes.
    #
    # NOTE WELL -- this does not handle circular references at all.
    def to_doc(o = self)
      o = EOStruct::eos o
      h = o._hash.clone
      h.each { |k, v|
        if v.kind_of? OpenStruct
          h[k] = to_doc(v)
        end
      }
      h
    end
  end
  
  # Shorthand for create_eos when an OpenStruct object may need to be wrapped.
  def eos(o)
    create_eos o
  end

  # Shorthand for create_eos when an OpenStruct object may need to be wrapped.
  def self.eos(o)
    create_eos o
  end

  # Create (or modify) a new Enhanced OpenStruct object.
  def self.create_eos(o = OpenStruct.new)    
    class << (o)
      include EOS
      alias_method :_hash, :deep_inspect
    end unless o.respond_to? :deep_inspect
    o
  end

  # Create (or modify) a new Enhanced OpenStruct object.
  def create_eos(o = OpenStruct.new)    
    class << (o)
      include EOS
      alias_method :_hash, :deep_inspect
    end unless o.respond_to? :deep_inspect
    o
  end

  # Convert document format to a nested EOS.
  # This shall be mixed in with the Hash class, hince the
  # default on doc to 'self'.
  def to_eos(doc = self)
    raise EOException("doc must be a Hash or nested hashes.") unless doc.kind_of? Hash
    o = create_eos
    doc.each { |k, v|
      o._hash[k.to_sym] = unless v.kind_of? Hash
                            v
                          else
                            to_eos(v)
                          end
    }
    o
  end
end

# Modify Hash so that we can have EOStruct#to_eos
# present!
class Hash
  include EOStruct
  private :create_eos
  private :eos
end
