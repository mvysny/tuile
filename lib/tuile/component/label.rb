# frozen_string_literal: true

module Tuile
  class Component
    # A label which shows static text. No word-wrapping; clips long lines.
    class Label < Component
      def initialize
        super
        @lines = []
        @clipped_lines = []
      end

      # @param text [String, nil] draws this text. May contain ANSI formatting.
      #   Clipped automatically.
      # @return [void]
      def text=(text)
        @lines = text.to_s.split("\n")
        @content_size = nil
        update_clipped_text
      end

      # @return [Size]
      def content_size
        @content_size ||= begin
          width = @lines.map { |line| Unicode::DisplayWidth.of(Rainbow.uncolor(line)) }.max || 0
          Size.new(width, @lines.size)
        end
      end

      # @return [void]
      def repaint
        clear_background
        height = rect.height.clamp(0, nil)
        lines_to_print = @clipped_lines.length.clamp(nil, height)
        (0..lines_to_print - 1).each do |index|
          screen.print TTY::Cursor.move_to(rect.left, rect.top + index), @clipped_lines[index]
        end
      end

      protected

      # @return [void]
      def on_width_changed
        super
        update_clipped_text
      end

      private

      # @return [void]
      def update_clipped_text
        len = rect.width.clamp(0, nil)
        clipped = @lines.map do |line|
          Strings::Truncation.truncate(line, length: len)
        end
        return if @clipped_lines == clipped

        @clipped_lines = clipped
        invalidate
      end
    end
  end
end
