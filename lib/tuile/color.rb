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
  # The 256-color palette gets the same treatment via {PALETTE_NAMES}:
  # `Color::CADET_BLUE`, `Color::DODGER_BLUE1`, `Color::GREY37`, … — the
  # standard xterm chart names for indices 16..255, each an exact palette cell.
  # {.coerce} accepts anything {.new} accepts plus `nil` (terminal default) and
  # an existing {Color} (returned as-is), so APIs that accept colors typically
  # take `[Color, nil]` and pass through {.coerce}.
  #
  # ```ruby
  # Color.new(:red)              # named
  # Color.new(42)                # 256-color palette
  # Color.new([255, 100, 0])     # RGB
  # Color::RED                   # constant
  # Color.palette(42)            # 256-color palette, explicit
  # Color.rgb(255, 100, 0)       # 24-bit RGB, explicit
  # Color.hex("#ff6400")         # 24-bit RGB from a CSS-style hex string
  # Color.coerce(:red)           # accepts raw forms, returns Color
  # Color.coerce(nil)            # nil → nil
  # ```
  #
  # Which entry point to use is a deliberate policy split. High-traffic
  # call sites ({StyledString} and friends) stay lenient and {.coerce} raw
  # forms — you don't want factory ceremony on every styled span.
  # Declaration sites ({Theme}, defined once per app) are strict and take
  # only {Color} instances, where `Color.palette(130)` documents itself in
  # a way the bare `130` (palette index? RGB channel?) does not.
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

    # A color from the 256-color palette (SGR 38;5;N / 48;5;N). Same as
    # `Color.new(index)`, but the name says what the bare integer is.
    #
    # @param index [Integer] palette index, 0..255.
    # @return [Color]
    # @raise [ArgumentError] when `index` is not an Integer in 0..255.
    def self.palette(index)
      raise ArgumentError, "invalid palette index: #{index.inspect}" unless index.is_a?(Integer)

      new(index)
    end

    # A 24-bit RGB color (SGR 38;2;R;G;B / 48;2;R;G;B). Same as
    # `Color.new([r, g, b])`, but with the channels spelled out.
    #
    # @param red [Integer] 0..255.
    # @param green [Integer] 0..255.
    # @param blue [Integer] 0..255.
    # @return [Color]
    # @raise [ArgumentError] when a channel is not an Integer in 0..255.
    def self.rgb(red, green, blue)
      new([red, green, blue])
    end

    # A 24-bit RGB color from a CSS-style hex string — for when the value
    # comes from a hex source (a designer's palette, a CSS variable). The
    # leading `#` is optional, digits are case-insensitive, and the CSS
    # 3-digit shorthand expands as in CSS (`"#345"` → `"#334455"`).
    # 4/8-digit alpha forms are rejected: SGR has no alpha channel, and
    # silently dropping it would lie about the rendered color.
    #
    # @param string [String] e.g. `"#333333"`, `"5F9EA0"`, `"#333"`.
    # @return [Color] same value form as {.rgb} — `Color.hex("#333") ==
    #   Color.rgb(51, 51, 51)`.
    # @raise [ArgumentError] when `string` is not 3 or 6 hex digits with
    #   an optional leading `#`.
    def self.hex(string)
      digits = string.delete_prefix("#") if string.is_a?(String)
      raise ArgumentError, "invalid hex color: #{string.inspect}" unless digits&.match?(/\A(\h{3}|\h{6})\z/)

      digits = digits.gsub(/\h/) { |d| d * 2 } if digits.length == 3
      new(digits.scan(/\h{2}/).map { |channel| channel.to_i(16) })
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

    # Names for the 256-color palette indices 16..255, from the standard
    # xterm chart (<https://www.ditig.com/256-colors-cheat-sheet>). A constant
    # per entry is pre-defined, an exact palette cell — no quantization:
    # `Color::CADET_BLUE == Color.palette(72)`. The chart names some cells
    # identically (`DeepSkyBlue4` covers 23, 24 *and* 25); the first
    # occurrence wins the constant and the remaining cells stay reachable via
    # {.palette}. Indices 0..15 are covered by the {COLOR_SYMBOLS} constants
    # instead — the symbolic SGR form respects the user's terminal scheme,
    # which a hard palette cell would not.
    # @return [Hash{Symbol => Integer}]
    PALETTE_NAMES = {
      GREY0: 16, NAVY_BLUE: 17, DARK_BLUE: 18, BLUE3: 19, BLUE1: 21,
      DARK_GREEN: 22, DEEP_SKY_BLUE4: 23, DODGER_BLUE3: 26, DODGER_BLUE2: 27,
      GREEN4: 28, SPRING_GREEN4: 29, TURQUOISE4: 30, DEEP_SKY_BLUE3: 31,
      DODGER_BLUE1: 33, GREEN3: 34, SPRING_GREEN3: 35, DARK_CYAN: 36,
      LIGHT_SEA_GREEN: 37, DEEP_SKY_BLUE2: 38, DEEP_SKY_BLUE1: 39,
      SPRING_GREEN2: 42, CYAN3: 43, DARK_TURQUOISE: 44, TURQUOISE2: 45,
      GREEN1: 46, SPRING_GREEN1: 48, MEDIUM_SPRING_GREEN: 49, CYAN2: 50,
      CYAN1: 51, DARK_RED: 52, DEEP_PINK4: 53, PURPLE4: 54, PURPLE3: 56,
      BLUE_VIOLET: 57, ORANGE4: 58, GREY37: 59, MEDIUM_PURPLE4: 60,
      SLATE_BLUE3: 61, ROYAL_BLUE1: 63, CHARTREUSE4: 64, DARK_SEA_GREEN4: 65,
      PALE_TURQUOISE4: 66, STEEL_BLUE: 67, STEEL_BLUE3: 68,
      CORNFLOWER_BLUE: 69, CHARTREUSE3: 70, CADET_BLUE: 72, SKY_BLUE3: 74,
      STEEL_BLUE1: 75, PALE_GREEN3: 77, SEA_GREEN3: 78, AQUAMARINE3: 79,
      MEDIUM_TURQUOISE: 80, CHARTREUSE2: 82, SEA_GREEN2: 83, SEA_GREEN1: 84,
      AQUAMARINE1: 86, DARK_SLATE_GRAY2: 87, DARK_MAGENTA: 90, DARK_VIOLET: 92,
      PURPLE: 93, LIGHT_PINK4: 95, PLUM4: 96, MEDIUM_PURPLE3: 97,
      SLATE_BLUE1: 99, YELLOW4: 100, WHEAT4: 101, GREY53: 102,
      LIGHT_SLATE_GREY: 103, MEDIUM_PURPLE: 104, LIGHT_SLATE_BLUE: 105,
      DARK_OLIVE_GREEN3: 107, DARK_SEA_GREEN: 108, LIGHT_SKY_BLUE3: 109,
      SKY_BLUE2: 111, DARK_SEA_GREEN3: 115, DARK_SLATE_GRAY3: 116,
      SKY_BLUE1: 117, CHARTREUSE1: 118, LIGHT_GREEN: 119, PALE_GREEN1: 121,
      DARK_SLATE_GRAY1: 123, RED3: 124, MEDIUM_VIOLET_RED: 126, MAGENTA3: 127,
      DARK_ORANGE3: 130, INDIAN_RED: 131, HOT_PINK3: 132, MEDIUM_ORCHID3: 133,
      MEDIUM_ORCHID: 134, MEDIUM_PURPLE2: 135, DARK_GOLDENROD: 136,
      LIGHT_SALMON3: 137, ROSY_BROWN: 138, GREY63: 139, MEDIUM_PURPLE1: 141,
      GOLD3: 142, DARK_KHAKI: 143, NAVAJO_WHITE3: 144, GREY69: 145,
      LIGHT_STEEL_BLUE3: 146, LIGHT_STEEL_BLUE: 147, YELLOW3: 148,
      DARK_SEA_GREEN2: 151, LIGHT_CYAN3: 152, LIGHT_SKY_BLUE1: 153,
      GREEN_YELLOW: 154, DARK_OLIVE_GREEN2: 155, DARK_SEA_GREEN1: 158,
      PALE_TURQUOISE1: 159, DEEP_PINK3: 161, MAGENTA2: 165, HOT_PINK2: 169,
      ORCHID: 170, MEDIUM_ORCHID1: 171, ORANGE3: 172, LIGHT_PINK3: 174,
      PINK3: 175, PLUM3: 176, VIOLET: 177, LIGHT_GOLDENROD3: 179, TAN: 180,
      MISTY_ROSE3: 181, THISTLE3: 182, PLUM2: 183, KHAKI3: 185,
      LIGHT_GOLDENROD2: 186, LIGHT_YELLOW3: 187, GREY84: 188,
      LIGHT_STEEL_BLUE1: 189, YELLOW2: 190, DARK_OLIVE_GREEN1: 191,
      HONEYDEW2: 194, LIGHT_CYAN1: 195, RED1: 196, DEEP_PINK2: 197,
      DEEP_PINK1: 198, MAGENTA1: 201, ORANGE_RED1: 202, INDIAN_RED1: 203,
      HOT_PINK: 205, DARK_ORANGE: 208, SALMON1: 209, LIGHT_CORAL: 210,
      PALE_VIOLET_RED1: 211, ORCHID2: 212, ORCHID1: 213, ORANGE1: 214,
      SANDY_BROWN: 215, LIGHT_SALMON1: 216, LIGHT_PINK1: 217, PINK1: 218,
      PLUM1: 219, GOLD1: 220, NAVAJO_WHITE1: 223, MISTY_ROSE1: 224,
      THISTLE1: 225, YELLOW1: 226, LIGHT_GOLDENROD1: 227, KHAKI1: 228,
      WHEAT1: 229, CORNSILK1: 230, GREY100: 231, GREY3: 232, GREY7: 233,
      GREY11: 234, GREY15: 235, GREY19: 236, GREY23: 237, GREY27: 238,
      GREY30: 239, GREY35: 240, GREY39: 241, GREY42: 242, GREY46: 243,
      GREY50: 244, GREY54: 245, GREY58: 246, GREY62: 247, GREY66: 248,
      GREY70: 249, GREY74: 250, GREY78: 251, GREY82: 252, GREY85: 253,
      GREY89: 254, GREY93: 255
    }.freeze

    PALETTE_NAMES.each do |name, index|
      const_set(name, new(index))
    end
  end
end
