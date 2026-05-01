# frozen_string_literal: true

module Tuile
  # A mouse event.
  #
  # @!attribute [r] button
  #   @return [Symbol, nil] one of `:left`, `:middle`, `:right`, `:scroll_up`,
  #     `:scroll_down`; `nil` if not known.
  # @!attribute [r] x
  #   @return [Integer] x coordinate, 0-based.
  # @!attribute [r] y
  #   @return [Integer] y coordinate, 0-based.
  class MouseEvent < Data.define(:button, :x, :y)
    # Checks whether given key is a mouse event key
    # @param key [String] key read via {Keys.getkey}
    # @return [Boolean] true if it is a mouse event
    def self.mouse_event?(key)
      key.start_with?("\e[M") && key.size >= 6
    end

    # @param key [String] key read via {Keys.getkey}
    # @return [MouseEvent, nil]
    def self.parse(key)
      return nil unless mouse_event?(key)

      button = key[3].ord - 32
      # XTerm reports coordinates 1-based (column N is encoded as N + 32);
      # subtract 33 so that `x` and `y` are 0-based.
      x = key[4].ord - 33
      y = key[5].ord - 33
      button = case button
               when 0 then :left
               when 2 then :right
               when 1 then :middle
               when 64 then :scroll_up
               when 65 then :scroll_down
               end
      MouseEvent.new(button, x, y)
    end

    # @return [String]
    def self.start_tracking = "\e[?1000h"
    # @return [String]
    def self.stop_tracking = "\e[?1000l"
  end
end
