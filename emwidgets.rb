=begin rdoc
=EmWidgets -- Widgets for Embracer
Here we have customized FOX widgets specifically for the Embracer Platform.

=end

require 'fox16'
require 'fox16/colors'

include Fox

=begin rdoc
=EMBidAskSizer -- show graphically the relative relationship of Bid and Ask.

The Bid and Ask values and sizes are dymanically changing, and varying wildly. 
To eyeball the raw values and compare them can take quite a bit of attention.
What we do with this widget is to graphically display that dynamic relationship
so that the user can see at a glance what is going on.

Simply call the updateBidAsk() method witht the latest reading, and it will
be instantly reflected in this widget.

=end

class EMBidAskSizer < FXVerticalFrame
  def initialize(*parms)
    super(*parms)    
    @canvas = FXCanvas.new(self, :opts =>  LAYOUT_FILL_X|LAYOUT_FILL_Y|LAYOUT_TOP|LAYOUT_LEFT)
    @canvas.connect(SEL_PAINT, method(:onCanvasRepaint))
    @bidColor = FXColor::Green
    @askColor = FXColor::Red
    @tradeSizeColor = FXColor::Black
    @backgroundColor = FXColor::White
    @quote = nil
  end
  
  attr_accessor :bidColor, :askColor, :backgroundColor, :tradeSizeColor

  # Call this whenever there is an update to the bid and ask sizes
  def updateQuote(quote)
    @quote = quote
    onCanvasRepaint(nil, nil, nil)
  end

  def onCanvasRepaint(sender, sel, event)
    FXDCWindow.new(@canvas) { |dc|
      dc.foreground = @backgroundColor
      dc.fillRectangle(0, 0, @canvas.width, @canvas.height)

      unless @quote.nil?
        moid = (0.0 + @quote.bidSize - @quote.askSize) / (0.0 + @quote.bidSize + @quote.askSize)
        moid = 0 unless moid.finite?
        r = [([@canvas.width, @canvas.height].min / 2.0) * moid.abs, 2].max
        xmid = @canvas.width / 2
        x = xmid + xmid * moid 
        y = @canvas.height / 2
        lw = @quote.tradeSize * 2
        lx = x - lw / 2
        
        # Draw a rectangle representing the trade size.
        dc.foreground = @tradeSizeColor
        dc.fillRectangle(lx, 0, lw, @canvas.height)

        # Draw a circle representing the relationship between bid size and ask size, 
        # and also a position corresponding to the same.
        dc.foreground = if moid > 0
                          @bidColor
                        else
                          @askColor
                        end
        dc.fillCircle(x, y, r)
      end
    }
  end
end
