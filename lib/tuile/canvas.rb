# frozen_string_literal: true

module Tuile
  # The surface a component paints onto — the seam between {Component}'s three
  # drawing helpers and wherever the cells actually land. A component never
  # picks one: it paints onto the canvas its {Component#repaint} was handed, and
  # {Screen#repaint} hands one to every component it drains.
  #
  #   component.repaint(canvas)   # paint it somewhere other than the back buffer
  #
  # Three methods, the same three {Buffer} offers, in absolute screen
  # coordinates. Writes outside the surface are dropped rather than raising,
  # which is what lets a component paint a row the terminal is too narrow for
  # without checking first.
  #
  # Subclass to change where the cells go, never to change what a component
  # draws. {Canvas::Direct}, the only one today, paints straight into
  # {Screen#buffer}, so an ordinary frame costs one forwarding call.
  #
  # UI-thread-confined.
  class Canvas
    # Writes a {StyledString} starting at `(x, y)`, advancing by each grapheme's
    # display width.
    # @param x [Integer] starting column, absolute.
    # @param y [Integer] row, absolute.
    # @param styled [StyledString] the text of one row; newlines are not handled.
    # @return [void]
    def set_text(x, y, styled) = raise(NotImplementedError, "#{self.class}#set_text")

    # Writes one grapheme cluster at `(x, y)`.
    # @param x [Integer] column, absolute.
    # @param y [Integer] row, absolute.
    # @param grapheme [String] one grapheme cluster.
    # @param style [StyledString::Style]
    # @return [void]
    def set_char(x, y, grapheme, style = StyledString::Style::DEFAULT) =
      raise(NotImplementedError, "#{self.class}#set_char")

    # Fills `rect` with blank cells in `style` — only the `bg` shows.
    # @param rect [Rect] absolute.
    # @param style [StyledString::Style]
    # @return [void]
    def fill(rect, style = StyledString::Style::DEFAULT) = raise(NotImplementedError, "#{self.class}#fill")
  end
end
