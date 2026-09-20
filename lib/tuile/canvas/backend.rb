# frozen_string_literal: true

module Tuile
  class Canvas
    # Where a {Canvas}'s cells land: three primitives taking a fully resolved
    # style. Include it to *be* one — {Tuile::Buffer} does, and needs no adapter:
    #
    #   Canvas.new(screen.buffer)
    #
    # A backend is dumb by contract: no theme, no component, no background
    # chain, no translation, and no default arguments — the canvas resolves all
    # of that and hands down a whole style at a coordinate in the backend's own
    # grid. What varies here is only *where* the cells go;
    # how a write is transformed on the way there belongs to the {Canvas}, which
    # is final. See `D_canvas`.
    #
    # **`include`, never `prepend`.** A class's own methods win over an included
    # module's, which is what lets {Tuile::Buffer} carry this while defining all
    # three itself; prepended, these bodies would sit *ahead* of the class and
    # every write would raise.
    #
    # Out-of-range writes are **dropped, not raised** — the terminal-edge clip
    # belongs here, which is what lets a component paint a row the terminal is
    # too narrow for without checking first.
    module Backend
      # @param x [Integer] starting column, in this backend's own grid —
      #   the canvas has already applied its {Canvas#origin}.
      # @param y [Integer] row, likewise.
      # @param styled [StyledString] the text of one row; newlines are not handled.
      # @return [void]
      def set_text(x, y, styled) = raise(NotImplementedError, "#{self.class}#set_text")

      # @param x [Integer] column, in this backend's own grid.
      # @param y [Integer] row, likewise.
      # @param grapheme [String] one grapheme cluster.
      # @param style [StyledString::Style] fully resolved.
      # @return [void]
      def set_char(x, y, grapheme, style) = raise(NotImplementedError, "#{self.class}#set_char")

      # @param rect [Rect] in this backend's own grid.
      # @param style [StyledString::Style] fully resolved; only its `bg` shows.
      # @return [void]
      def fill(rect, style) = raise(NotImplementedError, "#{self.class}#fill")
    end
  end
end
