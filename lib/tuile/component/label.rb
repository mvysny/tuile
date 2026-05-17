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
        @clipped_lines = []
        @blank_line = ""
      end

      # @return [StyledString] the current text. Defaults to an empty
      #   {StyledString}.
      attr_reader :text

      # Replaces the text. A `String` is parsed via {StyledString.parse}
      # (embedded ANSI is honored); a `StyledString` is used as-is. `nil` is
      # coerced to an empty {StyledString}; any other object is coerced via
      # `to_s` first. Lines wider than {#rect} are truncated with an
      # ellipsis at paint time.
      # @param value [String, StyledString, nil]
      # @return [void]
      def text=(value)
        new_text = coerce_to_styled(value)
        return if @text == new_text

        @text = new_text
        @content_size = nil
        update_clipped_lines
        invalidate
      end

      # @return [Size] longest hard-line's display width × number of hard
      #   lines. Reported on the *unclipped* text — sizing is intrinsic to
      #   the content, not the viewport. Empty text returns `Size.new(0, 0)`.
      def content_size
        @content_size ||=
          if @text.empty?
            Size.new(0, 0)
          else
            hard_lines = @text.lines
            width = hard_lines.map(&:display_width).max || 0
            Size.new(width, hard_lines.size)
          end
      end

      # Paints the text into {#rect}.
      #
      # Skips the {Component#repaint} default's auto-clear: every row is
      # painted explicitly (with pre-padded blanks past the last line), so
      # the "fully draw over your rect" contract is met without an upfront
      # wipe.
      # @return [void]
      def repaint
        return if rect.empty? || rect.left.negative? || rect.top.negative?

        (0...rect.height).each do |row|
          line = @clipped_lines[row] || @blank_line
          screen.print TTY::Cursor.move_to(rect.left, rect.top + row), line
        end
      end

      protected

      # @return [void]
      def on_width_changed
        super
        update_clipped_lines
      end

      private

      # @param input [Object]
      # @return [StyledString]
      def coerce_to_styled(input)
        case input
        when nil then StyledString::EMPTY
        when StyledString then input
        else StyledString.parse(input.to_s)
        end
      end

      # Recomputes {@clipped_lines} for the current text and rect width.
      # Each line is ellipsized to fit, padded with trailing spaces out to
      # the full width, and pre-rendered to ANSI so {#repaint} is just a
      # lookup + screen.print per row. {@blank_line} covers rows past the
      # last text line.
      # @return [void]
      def update_clipped_lines
        width = rect.width.clamp(0, nil)
        @blank_line = " " * width
        @clipped_lines = @text.lines.map { |line| pad_to(line.ellipsize(width), width).to_ansi }
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
