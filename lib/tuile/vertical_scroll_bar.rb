# frozen_string_literal: true

module Tuile
  # A vertical scrollbar that computes which character to draw at each row.
  #
  # Uses `█` for the handle (filled track) and `░` for the empty track. There
  # are no up/down arrows; the full height is used as the track. Handle
  # geometry is precomputed in the constructor as {#handle_height},
  # {#handle_start}, and {#handle_end}.
  class VerticalScrollBar
    # @return [Integer] number of track rows the handle occupies (height >= 1
    #   only).
    attr_reader :handle_height
    # @return [Integer] 0-based row where the handle starts (height >= 1 only).
    attr_reader :handle_start
    # @return [Integer] 0-based row where the handle ends (height >= 1 only).
    attr_reader :handle_end

    # @param height [Integer] number of rows in the scrollbar (== viewport
    #   height).
    # @param line_count [Integer] total number of content lines.
    # @param top_line [Integer] index of the first visible content line.
    def initialize(height, line_count:, top_line:)
      @height = height

      return unless height >= 1

      if line_count <= height
        @handle_height = height
        @handle_start  = 0
        @handle_end    = height - 1
      else
        @handle_height = [(height * height / line_count.to_f).ceil, 1].max
        @handle_start  = (height * top_line / line_count.to_f).floor
        @handle_end    = @handle_start + @handle_height - 1
      end
    end

    # Returns the scrollbar character for the given viewport row.
    # @param row_in_viewport [Integer] 0-based row index within the viewport.
    # @return [String] single scrollbar character.
    def scrollbar_char(row_in_viewport)
      row_in_viewport >= @handle_start && row_in_viewport <= @handle_end ? "█" : "░"
    end
  end
end
