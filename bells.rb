=begin rdoc
= Bells -- various audible alerts for EMbracer.

We need to have various audible alerts for use by EMbracer to get the
attention of the user for when, say, a security is bought or sold, or
some other event happens.

For this reason, we have this module. Simply call one of the bells and
it will play.

This module relies on RubyGame to play the sound. Should work on 
Windows as well as Linux.
=end
begin
  require 'rubygame'
  include Rubygame
  RG = true
rescue LoadError # load problem
  RG = false
end


=begin rdoc
= Bells Mixin for playing audio bits.
=end
module Bells
  # List of sounds to preload.
  if RG
    begin
      BELLS = {
        :startup => Sound.load("audio/mgenter.wav"),
        exit: Sound.load("audio/mgexit.wav"),
        entered_position: Sound.load("audio/laser1.wav"),
        exited_position: Sound.load("audio/laser2.wav"),
        warning: Sound.load("audio/Buzz.wav"),
        error: Sound.load("audio/eiree_error_sound.wav"),
        beep: Sound.load("audio/beep.wav"),
        click: Sound.load("audio/click.wav"),
        armed: Sound.load("audio/alex1.wav"),
        unarmed: Sound.load("audio/you_wimp.wav"),
        reverting: Sound.load("audio/Ohno.wav"),
        filled:  Sound.load("audio/Yea.wav"),
      }
    rescue # quiet failure.
    end
    BELLS.each { |sym, sound|
      module_eval %{
        # This is the #{sym} bell.
        def bell_#{sym}
          begin
            BELLS[:#{sym}].play if RG
          rescue # die quietly if there's a problem.
          end
       end }
     }
  else # RubyGame not available
   # We are goingto have to rework this. FIX!!!
  end
end

# Testing
if __FILE__ == $0
  include Bells

  BELLS.each { |name, sound|
    puts "playing #{name}..."
    BELLS[name].play
    sleep 0.5
  }


  puts "Testing the Bells module"
  bell_error
  sleep 1
  bell_exited_position
  sleep 1
  bell_beep
  sleep 1
end
