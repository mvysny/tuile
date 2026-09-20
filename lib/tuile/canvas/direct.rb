# frozen_string_literal: true

module Tuile
  class Canvas
    # A {Canvas} that paints straight into a {Buffer}, cell for cell, with
    # nothing in between. What {Screen} installs at construction, so an ordinary
    # frame reaches the back buffer through one forwarding call:
    #
    #   Canvas::Direct.new(screen.buffer)
    #
    # It holds the buffer, not a copy of its geometry, so a {Buffer#resize}
    # needs no new canvas.
    #
    # UI-thread-confined.
    class Direct < Canvas
      # @return [Buffer] the buffer being painted into.
      attr_reader :buffer

      # @param buffer [Buffer]
      def initialize(buffer)
        super()
        @buffer = buffer
      end

      # (see Canvas#set_text)
      def set_text(x, y, styled) = @buffer.set_text(x, y, styled)

      # (see Canvas#set_char)
      def set_char(x, y, grapheme, style = StyledString::Style::DEFAULT) = @buffer.set_char(x, y, grapheme, style)

      # (see Canvas#fill)
      def fill(rect, style = StyledString::Style::DEFAULT) = @buffer.fill(rect, style)
    end
  end
end
