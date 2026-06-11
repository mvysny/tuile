# frozen_string_literal: true

module Tuile
  class Component
    # A label which shows static text. No word-wrapping; long lines are
    # truncated with an ellipsis. Text is modeled as a {StyledString};
    # {#text=} accepts a {String} (parsed via {StyledString.parse}, so
    # embedded ANSI is honored) or a {StyledString} directly. {#text}
    # always returns the {StyledString}.
    class Label < Component
      def initialize
        super
        @text = StyledString::EMPTY
        @bg = nil
        @clipped_lines = []
        @blank_line = ""
      end

      # @return [StyledString] the current text. Defaults to an empty
      #   {StyledString}.
      attr_reader :text

      # @return [Color, nil] background color applied uniformly across every
      #   painted row (including padding past the text). `nil` (default)
      #   leaves whatever bg the text's own styling carries.
      attr_reader :bg

      # Replaces the text. A `String` is parsed via {StyledString.parse}
      # (embedded ANSI is honored); a `StyledString` is used as-is; `nil` is
      # coerced to an empty {StyledString}. Lines wider than {#rect} are
      # truncated with an ellipsis at paint time.
      # @param value [String, StyledString, nil]
      # @return [void]
      def text=(value)
        new_text = StyledString.parse(value)
        return if @text == new_text

        @text = new_text
        update_clipped_lines
        invalidate
        self.content_size = compute_content_size
      end

      # Sets the background color. Coerced via {Color.coerce}, so a Symbol,
      # Integer, Array, {Color}, or `nil` all work. `nil` clears the override
      # — the label paints with whatever bg the text's own styling provides.
      # Otherwise the bg overlays every span (including the trailing pad and
      # blank rows past the last text line).
      #
      # @param value [Color, Symbol, Integer, Array<Integer>, nil]
      # @return [void]
      def bg=(value)
        new_bg = Color.coerce(value)
        return if @bg == new_bg

        @bg = new_bg
        update_clipped_lines
        invalidate
      end

      # Paints the text into {#rect}.
      #
      # Skips the {Component#repaint} default's auto-clear: every row is
      # painted explicitly (with pre-padded blanks past the last line), so
      # the "fully draw over your rect" contract is met without an upfront
      # wipe.
      # @return [void]
      def repaint
        return if rect.empty?

        (0...rect.height).each do |row|
          line = @clipped_lines[row] || @blank_line
          screen.buffer.set_line(rect.left, rect.top + row, line)
        end
      end

      protected

      # @return [void]
      def on_width_changed
        super
        update_clipped_lines
      end

      private

      # Natural size: longest hard-line's display width × number of hard
      # lines. Computed on the *unclipped* text — sizing is intrinsic to the
      # content, not the viewport. Empty text yields {Size::ZERO}.
      # @return [Size]
      def compute_content_size
        return Size::ZERO if @text.empty?

        hard_lines = @text.lines
        width = hard_lines.map(&:display_width).max || 0
        Size.new(width, hard_lines.size)
      end

      # Recomputes {@clipped_lines} for the current text and rect width.
      # Each line is ellipsized to fit and padded with trailing spaces out to
      # the full width, so {#repaint} is just a lookup + {Buffer#set_line} per
      # row. {@blank_line} covers rows past the last text line. When {#bg} is
      # set, every produced line (and the blank row) has the bg applied
      # uniformly.
      # @return [void]
      def update_clipped_lines
        width = rect.width.clamp(0, nil)
        @blank_line = apply_bg(StyledString.plain(" " * width))
        @clipped_lines = @text.lines.map { |line| apply_bg(pad_to(line.ellipsize(width), width)) }
      end

      # @param line [StyledString]
      # @return [StyledString]
      def apply_bg(line)
        @bg ? line.with_bg(@bg) : line
      end

      # @param line [StyledString]
      # @param width [Integer]
      # @return [StyledString]
      def pad_to(line, width)
        diff = width - line.display_width
        return line if diff <= 0

        line + StyledString.plain(" " * diff)
      end
    end
  end
end
