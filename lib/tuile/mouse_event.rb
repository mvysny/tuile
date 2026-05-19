# frozen_string_literal: true

module Tuile
  # A mouse event.
  #
  # @!attribute [r] button
  #   @return [Symbol, nil] one of `:left`, `:middle`, `:right`, `:scroll_up`,
  #     `:scroll_down`, `:scroll_left`, `:scroll_right`; `nil` if not known.
  # @!attribute [r] x
  #   @return [Integer] x coordinate, 0-based.
  # @!attribute [r] y
  #   @return [Integer] y coordinate, 0-based.
  class MouseEvent < Data.define(:button, :x, :y)
    # @return [Point] the event's position.
    def point = Point.new(x, y)

    # Checks whether given key is a mouse event key. Returns true on the X10
    # `\e[M` prefix regardless of length — {.parse} is the place that
    # validates the full 6-byte shape and raises on malformed input.
    # @param key [String] key read via {Keys.getkey}
    # @return [Boolean] true if it is a mouse event
    def self.mouse_event?(key)
      key.start_with?("\e[M")
    end

    # Parses an X10 mouse report (`\e[M` + 3 bytes: button, x, y).
    #
    # Raises {Tuile::Error} when `key` starts with the mouse prefix but is
    # not exactly 6 bytes long. Both shorter and longer inputs are bugs in
    # the upstream key-reader: a shorter prefix means the tail was lost on
    # the way in, and a longer one means we over-consumed into the next
    # escape sequence. We refuse to silently truncate either case because
    # the trailing `\e` of an over-read corrupts the *next* getkey, and the
    # corruption then surfaces as garbled keystrokes in focused inputs
    # rather than as a parser failure pointing at the actual cause.
    # @param key [String] key read via {Keys.getkey}
    # @return [MouseEvent, nil] `nil` if `key` is not a mouse event
    # @raise [Tuile::Error] if `key` is a malformed mouse event
    def self.parse(key)
      return nil unless mouse_event?(key)
      unless key.bytesize == 6
        raise Tuile::Error,
              "malformed mouse event: expected 6 bytes after \\e[M prefix, got #{key.bytesize}: #{key.inspect}"
      end

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
               when 66 then :scroll_left
               when 67 then :scroll_right
               end
      MouseEvent.new(button, x, y)
    end

    # @return [String]
    def self.start_tracking = "\e[?1000h"
    # @return [String]
    def self.stop_tracking = "\e[?1000l"
  end
end
