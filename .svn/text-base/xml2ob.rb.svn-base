# Convert XML to an object.
# Written in Ruby 1.9.1

module XML2Ob
  require "rexml/parsers/pullparser"
  require "eostruct"

  include EOStruct

  # Here we wish to be able to get the internal hash for ourselves. Besides,
  # we may need to modify the keys to something more to our liking.

  PullParser = REXML::Parsers::PullParser

  # Convert the given XML to an Object, with the
  # tag names as accessors in the object.
  #
  # The Object should be frozen, as there's
  # no solid reason to write to it.
  def convert(xml)
    open("xml.log", "a") { |f|
      f << "*" * 50
      f << "#{Time.new}\n"
      f << xml
      f << "\n"
    } if $logxml
    p = PullParser.new(xml)
    _convert(p)
  end

  # Recursive conversion. DO NOT CALL DIRECTLY from application code!
  # FIX!!! There are edge cases where an empty string will be converted into a nil
  def _convert(p)
    o = create_eos
    while p.has_next?
      element = nil
      pe = p.pull
      tok = if pe[0].strip == ''
              nil
            else
              pe[0].strip
            end
      case pe.event_type 

      when :start_element
        tok[0] = tok[0].downcase
        element = tok.to_sym
        val = _convert(p)
        if o._hash.key? element # already there?
          unless o._hash[element].kind_of? Array
            o._hash[element] = [o._hash[element], val]
          else
            o._hash[element] << val
          end  
        else
          o._hash[element] = val
        end
        
      when :text
        unless o.kind_of? OpenStruct
          o += tok
        else
          o = tok
        end unless tok.nil?

      when :end_element
        o = if (not o.kind_of? OpenStruct) or not o._hash.empty? 
              o
            else
              nil
            end
        return o
      end
    end
    o
  end
  private :_convert 
end

=begin rdoc
=The Translate Mixin
Mixin this module to do translation of fields in XML2Ob -- generated objects.

You'll need to define a @@MAPPER class constant array containing your
mappings. See the examples for a clue.
=end
module Translate

  # Translate given OpenStruct object to something The Embracer recognizes.
  # Assumes object was created by xml2ob.
  def translate(ob, mapper)
    ob._hash.clone.each {|k, v|
      if v.kind_of? Array
        v.each {|ao|
          translate(ao, mapper) if ao.kind_of? OpenStruct
        }
      elsif v.kind_of? OpenStruct
        translate(v, mapper)
      end
      
      if mapper.key? k and not mapper[k].nil?
        result = mapper[k].(k, v)
        result = [result] unless result[0].kind_of? Array
        result.each { |(nk, nv)|
          ob._hash[nk] = nv
        }
      end
    }
    ob
  end
end

