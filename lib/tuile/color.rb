# frozen_string_literal: true

module Tuile
  # An immutable terminal color. Accepts the three forms ANSI/SGR understands:
  #
  # - a Symbol from {COLOR_SYMBOLS} — 8 standard + 8 bright named colors
  #   (SGR 30..37 / 90..97 for fg, 40..47 / 100..107 for bg)
  # - an Integer 0..255 — the 256-color palette (SGR 38;5;N / 48;5;N)
  # - an Array of three Integers 0..255 — 24-bit RGB (SGR 38;2;R;G;B / 48;2;R;G;B)
  #
  # A constant per named color is pre-defined (`Color::RED`, `Color::BRIGHT_BLUE`,
  # …) so callers can reach for `Color::RED` instead of building one each time.
  # {.coerce} accepts anything {.new} accepts plus `nil` (terminal default) and
  # an existing {Color} (returned as-is), so APIs that accept colors typically
  # take `[Color, nil]` and pass through {.coerce}.
  #
  # ```ruby
  # Color.new(:red)              # named
  # Color.new(42)                # 256-color palette
  # Color.new([255, 100, 0])     # RGB
  # Color::RED                   # constant
  # Color.coerce(:red)           # accepts raw forms, returns Color
  # Color.coerce(nil)            # nil → nil
  # ```
  #
  # {#to_ansi} renders a full SGR escape (`"\e[31m"`); {#sgr_codes} returns the
  # raw numeric codes so callers (notably {StyledString}) can combine them with
  # other SGR attributes in a single sequence.
  class Color
    # Symbolic color names. Order is significant: indices 0..7 map to the
    # standard ANSI colors (SGR 30..37 fg / 40..47 bg); indices 8..15 map to
    # bright variants (SGR 90..97 / 100..107).
    # @return [Array<Symbol>]
    COLOR_SYMBOLS = %i[
      black red green yellow blue magenta cyan white
      bright_black bright_red bright_green bright_yellow
      bright_blue bright_magenta bright_cyan bright_white
    ].freeze

    # Coerces the input to a {Color}. `nil` passes through unchanged (callers
    # use `nil` for the terminal default); an existing {Color} is returned
    # as-is; otherwise the value is fed to {.new}.
    #
    # @param value [Color, Symbol, Integer, Array<Integer>, nil]
    # @return [Color, nil]
    # @raise [ArgumentError] when `value` is not one of the accepted forms.
    def self.coerce(value)
      case value
      when nil, Color then value
      else new(value)
      end
    end

    # @param value [Symbol, Integer, Array<Integer>] see class-level docs for
    #   the three accepted forms.
    # @raise [ArgumentError] when `value` is not one of the accepted forms.
    def initialize(value)
      unless COLOR_SYMBOLS.include?(value) ||
             (value.is_a?(Integer) && value.between?(0, 255)) ||
             (value.is_a?(Array) && value.length == 3 &&
              value.all? { |v| v.is_a?(Integer) && v.between?(0, 255) })
        raise ArgumentError, "invalid color: #{value.inspect}"
      end

      @value = value.is_a?(Array) ? value.dup.freeze : value
      freeze
    end

    # The underlying raw representation — a Symbol, Integer, or frozen
    # Array<Integer>.
    # @return [Symbol, Integer, Array<Integer>]
    attr_reader :value

    # SGR parameter codes for emitting this color as either a foreground
    # (`target: :fg`) or background (`target: :bg`). Returned as an array so
    # callers can splice them into a multi-attribute SGR (e.g. bold + color).
    #
    # @param target [Symbol] `:fg` or `:bg`.
    # @return [Array<Integer>]
    # @raise [ArgumentError] when `target` is neither `:fg` nor `:bg`.
    def sgr_codes(target = :fg)
      base, ext = case target
                  when :fg then [30, 38]
                  when :bg then [40, 48]
                  else raise ArgumentError, "target must be :fg or :bg, got #{target.inspect}"
                  end
      case @value
      when Symbol
        idx = COLOR_SYMBOLS.index(@value)
        idx < 8 ? [base + idx] : [base + 60 + (idx - 8)]
      when Integer then [ext, 5, @value]
      when Array then [ext, 2, *@value]
      end
    end

    # Full SGR escape sequence for this color (e.g. `"\e[31m"`). Useful for
    # `print`-style direct emission; for composing with other attributes use
    # {#sgr_codes} instead.
    #
    # @param target [Symbol] `:fg` or `:bg`.
    # @return [String]
    def to_ansi(target = :fg)
      "\e[#{sgr_codes(target).join(";")}m"
    end

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(Color) && @value == other.value
    end
    alias eql? ==

    # @return [Integer]
    def hash
      [self.class, @value].hash
    end

    # @return [String]
    def inspect
      "#<#{self.class.name} #{@value.inspect}>"
    end

    COLOR_SYMBOLS.each do |sym|
      const_set(sym.upcase, new(sym))
    end
  end
end
