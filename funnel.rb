=begin rdoc
Funnel created by Fred Mitchell (LinuxBloke.com) on 2010-06-05

=Funnel -- funnel calls to an object to a specific thread that created said object.

With some systems, like win32ole, the system basically wants to run on the same thread
the system was started on. To facillitate that need in a multithreaded environment,
we create the Funnel.

The Funnel wrapper on an object will basically intercept all method calls and
funnel those calls to the wrapped object in the thread it was created in. The
caller thead will basically block until the Funnel calls the target object's method
and will be given, as a return, the result object of that call.

The Funnel thread will basically sit in a loop waiting for something to come in,
and wake up to process the entries, then go back to sleep until the next ones come
in.

Any exceptions (or errors) that occur in the Funnel shall be 
thrown to the caller thread, as though the exception took place in that thread.

This code is released under the GPLv3.

=end

module Funnel
  class Wrapper
    def initialize(target)
      @targetOb = target
      @targetThr = Thread.current
      @targetThr[:methQueue] = [] if @targetThr[:methQueue].nil?
    end

    def method_missing(meth, *parms)
      Thread.current[:methResult] = :nothing_yet
      @targetThr[:methQueue] << [@targetOb, meth, Thread.current, parms]

      # Thing is, we may have gotten a response already!
      while Thread.current[:methResult] == :nothing_yet
        if @targetThr.stop?
          @targetThr.wakeup
          # Thread.stop
        end
        Thread.pass
      end
      Thread.current[:methResult]
    end
  end

  # Called by the orginal thread to process object messages.
  # This function never returns.
  def process_funnel_messages(loop_forever = true)
    begin
      meth = nil
      (ob, meth, thr, parms) = Thread.current[:methQueue].shift unless Thread.current[:methQueue].nil?
      unless meth.nil?
        begin
          thr[:methResult] = ob.send(meth, *parms)
          thr.run
        rescue
          thr.raise($!)
        end
      else 
        Thread.stop if loop_forever
      end
    end while loop_forever
  end

  def wrap(target)
    Wrapper.new(target)
  end
end
