# frozen_string_literal: true

module Tuile
  # The mouse: the events, their parser, and the tracking levels
  # {Screen#run_event_loop} asks the terminal for. Who gets one is
  # {Mouse::Router}'s story.
  #
  # Four of the five classes are what {.parse} reads off the wire; {DragEvent} is
  # the router's own, a move while something holds the grab. Each is a
  # `Data.define` including the {Event} marker — no inheritance, so a `case`
  # matches either one class or `Mouse::Event` for all of them. Enter and exit
  # have no class at all: nothing is parsed, they are the difference between two
  # hovered chains.
  #
  # Coordinates are screen-absolute and 0-based everywhere.
  module Mouse
    # Included by every mouse event class: a marker for `case`/`is_a?`, plus the
    # {#point} they share.
    module Event
      # @return [Point] the event's position.
      def point = Point.new(x, y)
    end

    # A button went down.
    #
    # @!attribute [r] button
    #   @return [Symbol] `:left`, `:middle` or `:right`.
    # @!attribute [r] x
    #   @return [Integer] 0-based column.
    # @!attribute [r] y
    #   @return [Integer] 0-based row.
    DownEvent = Data.define(:button, :x, :y) { include Event }

    # A button came up. **Deliberately no `button`**: an up reaches only the
    # component that claimed the press, and that grab already knows which button
    # it holds (`D_mouse_dispatch`).
    #
    # @!attribute [r] x
    #   @return [Integer] 0-based column.
    # @!attribute [r] y
    #   @return [Integer] 0-based row.
    UpEvent = Data.define(:x, :y) { include Event }

    # One wheel notch. A notch is not a button, which is why this is not a
    # {DownEvent}.
    #
    # @!attribute [r] direction
    #   @return [Symbol] `:up`, `:down`, `:left` or `:right`.
    # @!attribute [r] x
    #   @return [Integer] 0-based column.
    # @!attribute [r] y
    #   @return [Integer] 0-based row.
    ScrollEvent = Data.define(:direction, :x, :y) { include Event }

    # The pointer moved and nothing holds the grab.
    #
    # @!attribute [r] button
    #   @return [Symbol, nil] the button held while moving, or nil.
    # @!attribute [r] x
    #   @return [Integer] 0-based column.
    # @!attribute [r] y
    #   @return [Integer] 0-based row.
    MoveEvent = Data.define(:button, :x, :y) { include Event }

    # The pointer moved while a component holds the grab.
    #
    # @!attribute [r] button
    #   @return [Symbol] the button whose press took the grab.
    # @!attribute [r] x
    #   @return [Integer] 0-based column — may lie outside the grabbed
    #     component's rect, and even outside the screen's last known size.
    # @!attribute [r] y
    #   @return [Integer] 0-based row.
    DragEvent = Data.define(:button, :x, :y) { include Event }

    # The `capture_mouse:` levels, each a strict superset of the one before, and
    # each unlocking one tier of events: `:clicks` (mode 1000) gives
    # down, up and scroll; `:drag` (1002) adds drag; `:hover` (1003) adds move,
    # enter and exit (`R_mouse_reporting`).
    # @return [Array<Symbol>]
    LEVELS = %i[clicks drag hover].freeze

    # @return [Hash{Symbol => Integer}] the DEC private mode each level sets.
    MODES = { clicks: 1000, drag: 1002, hover: 1003 }.freeze
    private_constant :MODES

    # X10 button code layout: `button | 4 shift | 8 meta | 16 ctrl | 32 motion |
    # 64 wheel`, button 3 meaning "released" (`R_mouse_reporting`).
    # @return [Integer]
    MODIFIER_BITS = 4 | 8 | 16
    private_constant :MODIFIER_BITS

    class << self
      # Normalizes a `capture_mouse:` argument to a level.
      # @param capture_mouse [Boolean, Symbol] `false`, `true` (== `:clicks`),
      #   or one of {LEVELS}.
      # @return [Symbol, nil] the level; nil when tracking is off.
      # @raise [ArgumentError] on anything else.
      def level(capture_mouse)
        case capture_mouse
        when false, nil then nil
        when true then :clicks
        when *LEVELS then capture_mouse
        else
          raise ArgumentError,
                "capture_mouse: expected true, false or one of #{LEVELS}, got #{capture_mouse.inspect}"
        end
      end

      # @param level [Symbol] one of {LEVELS}.
      # @return [String] the escape enabling that level.
      def start_tracking(level) = "\e[?#{MODES.fetch(level)}h"

      # @param level [Symbol] one of {LEVELS}.
      # @return [String] the escape disabling that level.
      def stop_tracking(level) = "\e[?#{MODES.fetch(level)}l"

      # Whether `key` is a mouse report. True on the X10 `\e[M` prefix
      # regardless of length — {.parse} is the place that validates the full
      # 6-byte shape and raises on malformed input.
      # @param key [String] key read via {Keys.getkey}
      # @return [Boolean]
      def report?(key) = key.start_with?("\e[M")

      # Parses an X10 mouse report (`\e[M` + 3 bytes: button, x, y) into one of
      # {DownEvent}, {UpEvent}, {ScrollEvent} or {MoveEvent}. Modifier bits are
      # ignored.
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
      # @return [Event, nil] `nil` if `key` is not a mouse report, or reports
      #   a wheel button beyond the four directions.
      # @raise [Tuile::Error] if `key` is a malformed mouse report
      def parse(key)
        return nil unless report?(key)
        unless key.bytesize == 6
          raise Tuile::Error,
                "malformed mouse event: expected 6 bytes after \\e[M prefix, got #{key.bytesize}: #{key.inspect}"
        end

        code = (key[3].ord - 32) & ~MODIFIER_BITS
        # XTerm reports coordinates 1-based (column N is encoded as N + 32);
        # subtract 33 so that `x` and `y` are 0-based.
        x = key[4].ord - 33
        y = key[5].ord - 33
        low = code & 3
        if code.anybits?(64)
          direction = %i[up down left right][low]
          direction && ScrollEvent.new(direction, x, y)
        elsif code.anybits?(32)
          MoveEvent.new(button(low), x, y)
        elsif low == 3
          UpEvent.new(x, y)
        else
          DownEvent.new(button(low), x, y)
        end
      end

      private

      # @param low [Integer] the code's two low bits.
      # @return [Symbol, nil]
      def button(low) = %i[left middle right][low]
    end
  end
end
