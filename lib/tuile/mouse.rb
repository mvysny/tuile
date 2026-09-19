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
    #
    # The include must stay qualified — a bare `Event` in this namespace
    # resolves right back to here, and the gem-wide marker would be silently
    # lost.
    module Event
      include Tuile::Event

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
    # The one event {Router} *makes* rather than routes, so posting one to
    # {Screen#handle_mouse} raises: drive a grabbed component with a
    # {MoveEvent} carrying the held button, or with {FakeScreen#drag}.
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

    # The SGR encoding mode, requested alongside whichever {MODES} rung the
    # level picked — encoding and reporting are orthogonal modes. A terminal
    # that does not understand it ignores the DECSET and keeps sending X10
    # (`R_mouse_reporting`).
    # @return [Integer]
    SGR_MODE = 1006
    private_constant :SGR_MODE

    # Button code layout, shared by both encodings: `button | 4 shift | 8 meta
    # | 16 ctrl | 32 motion | 64 wheel` (`R_mouse_reporting`).
    # @return [Integer]
    MODIFIER_BITS = 4 | 8 | 16
    private_constant :MODIFIER_BITS

    # @return [String] the X10 report prefix, followed by three biased bytes.
    X10_PREFIX = "\e[M"
    private_constant :X10_PREFIX

    # @return [String] the SGR report prefix, followed by a {SGR_REPORT} body.
    SGR_PREFIX = "\e[<"
    private_constant :SGR_PREFIX

    # `\e[<Cb;x;y` then `M` for a press and `m` for a release — decimal and
    # uncapped, where X10 packs each coordinate into a byte and dies past 223.
    # @return [Regexp]
    SGR_REPORT = /\A\e\[<(\d+);(\d+);(\d+)([Mm])\z/
    private_constant :SGR_REPORT

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

      # The escape asking for that level, SGR encoding included:
      #
      #   Mouse.start_tracking(:clicks)   # => "\e[?1006h\e[?1000h"
      #
      # @param level [Symbol] one of {LEVELS}.
      # @return [String] the escape enabling that level.
      def start_tracking(level) = "\e[?#{SGR_MODE}h\e[?#{MODES.fetch(level)}h"

      # @param level [Symbol] one of {LEVELS}.
      # @return [String] the escape disabling that level, reporting first.
      def stop_tracking(level) = "\e[?#{MODES.fetch(level)}l\e[?#{SGR_MODE}l"

      # Whether `key` is a mouse report — the X10 `\e[M` prefix or the SGR
      # `\e[<` one, regardless of length. {.parse} is the place that validates
      # the full shape and raises on malformed input.
      # @param key [String] key read via {Keys.getkey}
      # @return [Boolean]
      def report?(key) = key.start_with?(X10_PREFIX, SGR_PREFIX)

      # Parses a mouse report in either wire encoding into one of {DownEvent},
      # {UpEvent}, {ScrollEvent} or {MoveEvent}. Modifier bits are ignored.
      #
      #   Mouse.parse("\e[M !\"")        # => X10:  DownEvent[:left, 0, 0]
      #   Mouse.parse("\e[<0;1;1M")      # => SGR:  DownEvent[:left, 0, 0]
      #   Mouse.parse("\e[<0;1;1m")      # => SGR:  UpEvent[0, 0]
      #
      # Which encoding arrived is invisible in the result, deliberately: SGR
      # names the button on a release and X10 cannot, so the button is dropped
      # (`D_mouse_dispatch`).
      #
      # A prefix without a whole well-formed report raises rather than
      # truncates: it is always a bug in the upstream key-reader — a short read
      # lost the tail, a long one over-consumed into the next escape sequence —
      # and swallowing it corrupts the *next* getkey, surfacing as garbled
      # keystrokes in focused inputs rather than as a parser failure pointing at
      # the cause.
      # @param key [String] key read via {Keys.getkey}
      # @return [Mouse::Event, nil] `nil` if `key` is not a mouse report, or reports
      #   a wheel button beyond the four directions.
      # @raise [Tuile::Error] if `key` is a malformed mouse report
      def parse(key)
        return nil unless report?(key)

        key.start_with?(SGR_PREFIX) ? parse_sgr(key) : parse_x10(key)
      end

      private

      # @param key [String] a report known to carry {X10_PREFIX}.
      # @return [Mouse::Event, nil]
      def parse_x10(key)
        unless key.bytesize == 6
          raise Tuile::Error,
                "malformed mouse event: expected 6 bytes after \\e[M prefix, got #{key.bytesize}: #{key.inspect}"
        end

        code = (key[3].ord - 32) & ~MODIFIER_BITS
        # Coordinates are 1-based and biased by 32, so - 33 lands them 0-based.
        # X10's release is the anonymous code 3 exactly: button-less motion is
        # 32 | 3 and the rightwards wheel 64 | 3, neither of them an up.
        event(code, key[4].ord - 33, key[5].ord - 33, released: code == 3)
      end

      # @param key [String] a report known to carry {SGR_PREFIX}.
      # @return [Mouse::Event, nil]
      def parse_sgr(key)
        match = SGR_REPORT.match(key)
        unless match
          raise Tuile::Error,
                "malformed mouse event: expected \\e[<Cb;x;y and M or m, got #{key.inspect}"
        end

        code, x, y = match.values_at(1, 2, 3).map(&:to_i)
        event(code & ~MODIFIER_BITS, x - 1, y - 1, released: match[4] == "m")
      end

      # The half both encodings share: a button code (unbiased, modifier bits
      # already cleared) and 0-based coordinates become an event.
      # @param code [Integer]
      # @param x [Integer]
      # @param y [Integer]
      # @param released [Boolean] whether the report says a button came up.
      # @return [Mouse::Event, nil]
      def event(code, x, y, released:)
        low = code & 3
        if code.anybits?(64)
          direction = %i[up down left right][low]
          direction && ScrollEvent.new(direction, x, y)
        elsif released
          UpEvent.new(x, y)
        elsif code.anybits?(32)
          MoveEvent.new(button(low), x, y)
        else
          DownEvent.new(button(low), x, y)
        end
      end

      # @param low [Integer] the code's two low bits.
      # @return [Symbol, nil]
      def button(low) = %i[left middle right][low]
    end
  end
end
