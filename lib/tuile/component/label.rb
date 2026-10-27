# frozen_string_literal: true

module Tuile
  class Component
    # A label which shows static text. Long lines are truncated with an
    # ellipsis, or word-wrapped with `wrap: true`:
    #
    #   status = Label.new("Ready")                      # one line, ellipsized
    #   finding = Label.new(explanation, wrap: true)     # a paragraph that never takes focus
    #
    # Text is modeled as a {StyledString}; {#text=} accepts a {String} (parsed
    # via {StyledString.parse}, so embedded ANSI is honored) or a
    # {StyledString} directly. {#text} always returns the {StyledString}.
    #
    # A wrapping label still never scrolls: rows past its rect are cut off, so
    # give it the height its {#measure_rows} answers, or use a {TextView}.
    class Label < Component
      # @param text [String, StyledString, nil] initial text, coerced the same
      #   way {#text=} coerces it (a `String` is parsed via
      #   {StyledString.parse}; `nil` is an empty label). Equivalent to
      #   constructing empty and assigning {#text=}.
      # @param wrap [Boolean] see {#wrap?}.
      def initialize(text = nil, wrap: false)
        super()
        @_text = StyledString::EMPTY
        @_wrap = wrap
        @_rows = []
        @_blank_row = ""
        self.text = text unless text.nil?
      end

      # @return [StyledString] the current text. Defaults to an empty
      #   {StyledString}.
      def text = @_text

      # @return [Boolean] whether a line wider than the rect word-wraps onto the
      #   next rows rather than being ellipsized. `false` by default.
      def wrap? = @_wrap

      # @param value [Boolean] see {#wrap?}.
      # @return [void]
      def wrap=(value)
        return if @_wrap == value

        @_wrap = value
        update_rows
        invalidate
        invalidate_rows
      end

      # The rows the text paints at `width`: one per line, or under {#wrap?} one
      # per wrapped row.
      #
      #   Label.new("one\ntwo").measure_rows(40)                       # => 2
      #   Label.new("a long sentence", wrap: true).measure_rows(6)     # => 3
      #
      # @param width [Integer]
      # @return [Integer] `0` for empty text.
      def measure_rows(width)
        return 0 if @_text.empty?

        wrap? ? @_text.wrap(width).size : @_text.lines.size
      end

      # Replaces the text. A `String` is parsed via {StyledString.parse}
      # (embedded ANSI is honored); a `StyledString` is used as-is; `nil` is
      # coerced to an empty {StyledString}. Lines wider than {#rect} are
      # truncated with an ellipsis at paint time.
      # @param value [String, StyledString, nil]
      # @return [void]
      def text=(value)
        new_text = StyledString.parse(value)
        return if @_text == new_text

        @_text = new_text
        update_rows
        invalidate
        invalidate_rows
      end

      # Paints the text into {#rect}.
      #
      # Skips the {Component#repaint} default's auto-clear: every row is
      # painted explicitly (with pre-padded blanks past the last line), so
      # the "fully draw over your rect" contract is met without an upfront
      # wipe. Rows go through {Canvas#set_text}, so the text, the trailing
      # padding and the blank rows all take {Component#bg_color}, and a span
      # that carries its own background keeps it.
      # @param canvas [Canvas] see {Component#repaint}.
      # @return [void]
      def repaint(canvas)
        return if rect.empty?

        (0...rect.height).each do |row|
          line = @_rows[row] || @_blank_row
          canvas.set_text(0, row, line)
        end
      end

      protected

      # Re-pads the rows to the new width; a height change costs a cheap
      # redundant pass, which beats keying the cache.
      # @return [void]
      def relayout
        super
        update_rows
      end

      private

      # Recomputes {@_rows} for the current text and rect width.
      # Each row is ellipsized to fit and padded with trailing spaces out to
      # the full width, so {#repaint} is just a lookup + {Buffer#set_text} per
      # row. {@_blank_row} covers rows past the last text line.
      # @return [void]
      def update_rows
        width = rect.width.clamp(0, nil)
        @_blank_row = StyledString.plain(" " * width)
        # Wrapped rows are ellipsized too: a cluster wider than the whole
        # width is the one row wrapping can't make fit.
        rows = wrap? ? @_text.wrap(width) : @_text.lines
        @_rows = rows.map { |row| row.ellipsize(width).ljust(width) }
      end
    end
  end
end
