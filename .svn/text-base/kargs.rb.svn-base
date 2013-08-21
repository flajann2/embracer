require 'arguments'

=begin rdoc
=KArgs Keyword Argument Mixin for Mixins and Classes

The arguments module only works for Classes, not Modules being
used as Mixins. KArgs attempts to address that deficiency.

If adding keyword arguments to a Class, the normal arguments 
methodology applies. If doing keyword arguments to a Module to
be used as a mixin, then you'll want to mixin KArgs to that module.

==NOTE WELL
This will make ALL methods keyword-like.

=end
module KArgs
  def args_list; @@args_list; end

  def self.included(mod)
    if mod.class == Module
      mod.extend ClassArguments

    elsif mod.class == Class
      class << mod
        alias :ca_new :new
        def new(*args, &block)
          named_args_for
          ca_new(*args, &block)
        end
      end
    end
  end

  module ClassArguments
    def included(mod)
      class << mod
        alias :ca_new :new
        def new(*args, &block)
          named_args_for
          ca_new(*args, &block)
        end
      end
    end
  end

  # Defaults for arguments of methods in Mixins or Classes
  #
  ## binding  -- the binding
  ## vars     -- local_variables
  ## defaults -- a hash of :var => default pairs
  #
  # Be sure to specify this as the first function in your method,
  # immediately after a "defaults" variable set to the hash of defaults.
  # In this way, you may have defaults to suit any need.
  #
  # Ex:
  ## def foo(a = :a, b = :b, c = :c)
  ##  defaults = {:a => "aye", :c => "see"}
  ##  argdef(binding, local_variables, defaults)
  ## end
  def argdef(binding, vars, defaults)
    vars.each { |var|
      e = eval(var, binding)
      # puts "#{var} => #{e}"
      if e.class == Symbol and defaults.member? e
        eval("#{var} = defaults[:#{e}]", binding)
      end
    }
  end  
end
