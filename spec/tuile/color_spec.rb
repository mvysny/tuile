# frozen_string_literal: true

module Tuile
  describe Color do
    describe ".new" do
      it "accepts a named symbol" do
        c = Color.new(:red)
        assert_equal :red, c.value
      end

      it "accepts a bright named symbol" do
        c = Color.new(:bright_blue)
        assert_equal :bright_blue, c.value
      end

      it "accepts a 256-color integer" do
        c = Color.new(42)
        assert_equal 42, c.value
      end

      it "accepts an RGB triple" do
        c = Color.new([255, 100, 0])
        assert_equal [255, 100, 0], c.value
      end

      it "freezes the RGB triple it holds" do
        triple = [10, 20, 30]
        c = Color.new(triple)
        assert c.value.frozen?
      end

      it "freezes the instance" do
        assert Color.new(:red).frozen?
      end

      it "raises on unknown symbol" do
        assert_raises(ArgumentError) { Color.new(:neon) }
      end

      it "raises on out-of-range integer" do
        assert_raises(ArgumentError) { Color.new(256) }
        assert_raises(ArgumentError) { Color.new(-1) }
      end

      it "raises on malformed RGB triple — short" do
        assert_raises(ArgumentError) { Color.new([255, 0]) }
      end

      it "raises on malformed RGB triple — out of range" do
        assert_raises(ArgumentError) { Color.new([255, 0, 256]) }
      end

      it "raises on malformed RGB triple — non-integer" do
        assert_raises(ArgumentError) { Color.new([255, 0, "z"]) }
      end

      it "raises on nil" do
        assert_raises(ArgumentError) { Color.new(nil) }
      end
    end

    describe ".palette" do
      it "constructs a 256-color palette entry" do
        assert_equal Color.new(42), Color.palette(42)
      end

      it "raises on out-of-range index" do
        assert_raises(ArgumentError) { Color.palette(256) }
        assert_raises(ArgumentError) { Color.palette(-1) }
      end

      it "raises on non-Integer input — :red is a named color, not a palette index" do
        assert_raises(ArgumentError) { Color.palette(:red) }
        assert_raises(ArgumentError) { Color.palette([1, 2, 3]) }
      end
    end

    describe ".rgb" do
      it "constructs a 24-bit RGB color" do
        assert_equal Color.new([255, 100, 0]), Color.rgb(255, 100, 0)
      end

      it "raises on out-of-range channel" do
        assert_raises(ArgumentError) { Color.rgb(255, 0, 256) }
        assert_raises(ArgumentError) { Color.rgb(-1, 0, 0) }
      end

      it "raises on non-Integer channel" do
        assert_raises(ArgumentError) { Color.rgb(255, 0, "z") }
      end
    end

    describe ".hex" do
      it "constructs a 24-bit RGB color from a hex string" do
        assert_equal Color.rgb(51, 51, 51), Color.hex("#333333")
      end

      it "treats the leading '#' as optional" do
        assert_equal Color.rgb(95, 158, 160), Color.hex("5f9ea0")
      end

      it "is case-insensitive" do
        assert_equal Color.hex("#5f9ea0"), Color.hex("#5F9EA0")
      end

      it "expands the CSS 3-digit shorthand" do
        assert_equal Color.rgb(51, 68, 85), Color.hex("#345")
        assert_equal Color.rgb(255, 255, 255), Color.hex("fff")
      end

      it "raises on alpha forms — SGR has no alpha channel" do
        assert_raises(ArgumentError) { Color.hex("#3456") }
        assert_raises(ArgumentError) { Color.hex("#33445566") }
      end

      it "raises on wrong digit counts" do
        assert_raises(ArgumentError) { Color.hex("#33") }
        assert_raises(ArgumentError) { Color.hex("#33445") }
        assert_raises(ArgumentError) { Color.hex("") }
        assert_raises(ArgumentError) { Color.hex("#") }
      end

      it "raises on non-hex digits" do
        assert_raises(ArgumentError) { Color.hex("#33z333") }
      end

      it "raises on non-String input" do
        assert_raises(ArgumentError) { Color.hex(0x333333) }
        assert_raises(ArgumentError) { Color.hex(nil) }
        assert_raises(ArgumentError) { Color.hex(:red) }
      end
    end

    describe ".coerce" do
      it "passes nil through" do
        assert_nil Color.coerce(nil)
      end

      it "passes a Color through" do
        c = Color.new(:red)
        assert_same c, Color.coerce(c)
      end

      it "constructs from a Symbol" do
        assert_equal Color::RED, Color.coerce(:red)
      end

      it "constructs from an Integer" do
        assert_equal Color.new(42), Color.coerce(42)
      end

      it "constructs from an RGB triple" do
        assert_equal Color.new([1, 2, 3]), Color.coerce([1, 2, 3])
      end

      it "raises on invalid input" do
        assert_raises(ArgumentError) { Color.coerce(:neon) }
      end

      it "rejects hex strings — Color.hex is the explicit entry point" do
        assert_raises(ArgumentError) { Color.coerce("#333333") }
      end
    end

    describe "named constants" do
      it "defines one constant per COLOR_SYMBOLS entry" do
        Color::COLOR_SYMBOLS.each do |sym|
          const = Color.const_get(sym.upcase)
          assert_instance_of Color, const
          assert_equal sym, const.value
        end
      end

      it "Color::RED equals Color.new(:red)" do
        assert_equal Color.new(:red), Color::RED
      end

      it "the constants are frozen" do
        assert Color::RED.frozen?
      end
    end

    describe "palette name constants" do
      it "defines one constant per PALETTE_NAMES entry" do
        Color::PALETTE_NAMES.each do |name, index|
          assert_equal Color.palette(index), Color.const_get(name)
        end
      end

      it "maps the xterm chart names to their exact palette cells" do
        assert_equal Color.palette(72), Color::CADET_BLUE
        assert_equal Color.palette(33), Color::DODGER_BLUE1
        assert_equal Color.palette(59), Color::GREY37
        assert_equal Color.palette(255), Color::GREY93
      end

      it "covers only indices 16..255 — 0..15 belong to the symbolic constants" do
        assert(Color::PALETTE_NAMES.values.all? { |i| i.between?(16, 255) })
      end

      it "maps each name to a distinct index" do
        indices = Color::PALETTE_NAMES.values
        assert_equal indices.uniq, indices
      end

      it "does not shadow the symbolic constants" do
        symbolic = Color::COLOR_SYMBOLS.map(&:upcase)
        assert_empty symbolic & Color::PALETTE_NAMES.keys
      end
    end

    describe "#sgr_codes" do
      it "returns SGR fg codes for standard symbols" do
        assert_equal [30], Color::BLACK.sgr_codes(:fg)
        assert_equal [31], Color::RED.sgr_codes(:fg)
        assert_equal [37], Color::WHITE.sgr_codes(:fg)
      end

      it "returns SGR fg codes for bright symbols" do
        assert_equal [90], Color::BRIGHT_BLACK.sgr_codes(:fg)
        assert_equal [91], Color::BRIGHT_RED.sgr_codes(:fg)
      end

      it "returns SGR bg codes for standard symbols" do
        assert_equal [41], Color::RED.sgr_codes(:bg)
      end

      it "returns SGR bg codes for bright symbols" do
        assert_equal [101], Color::BRIGHT_RED.sgr_codes(:bg)
      end

      it "returns 256-color fg codes" do
        assert_equal [38, 5, 42], Color.new(42).sgr_codes(:fg)
      end

      it "returns 256-color bg codes" do
        assert_equal [48, 5, 42], Color.new(42).sgr_codes(:bg)
      end

      it "returns RGB fg codes" do
        assert_equal [38, 2, 1, 2, 3], Color.new([1, 2, 3]).sgr_codes(:fg)
      end

      it "returns RGB bg codes" do
        assert_equal [48, 2, 1, 2, 3], Color.new([1, 2, 3]).sgr_codes(:bg)
      end

      it "defaults target to :fg" do
        assert_equal [31], Color::RED.sgr_codes
      end

      it "raises on unknown target" do
        assert_raises(ArgumentError) { Color::RED.sgr_codes(:underline) }
      end
    end

    describe "#to_ansi" do
      it "emits a full SGR escape for fg" do
        assert_equal "\e[31m", Color::RED.to_ansi(:fg)
      end

      it "emits a full SGR escape for bg" do
        assert_equal "\e[41m", Color::RED.to_ansi(:bg)
      end

      it "joins multi-code sequences with ';'" do
        assert_equal "\e[38;5;42m", Color.new(42).to_ansi(:fg)
        assert_equal "\e[48;2;1;2;3m", Color.new([1, 2, 3]).to_ansi(:bg)
      end

      it "defaults target to :fg" do
        assert_equal "\e[31m", Color::RED.to_ansi
      end
    end

    describe "#quantize" do
      context "returns the receiver when the depth can show it as-is" do
        it "keeps a named color at every depth" do
          ColorDepth::DEPTHS.each { assert_same Color::RED, Color::RED.quantize(_1) }
        end

        it "keeps a palette index above :ansi16" do
          c = Color.palette(67)
          assert_same c, c.quantize(:truecolor)
          assert_same c, c.quantize(:palette256)
        end

        it "keeps RGB at :truecolor" do
          c = Color.rgb(1, 2, 3)
          assert_same c, c.quantize(:truecolor)
        end
      end

      context "RGB to the 256-color palette" do
        it "maps an exact cube cell onto itself" do
          assert_equal Color.palette(67), Color.rgb(95, 135, 175).quantize(:palette256)
        end

        it "maps an exact grey-ramp cell onto itself" do
          assert_equal Color.palette(240), Color.rgb(88, 88, 88).quantize(:palette256)
        end

        it "prefers the grey ramp for a near-grey the cube approximates badly" do
          # grey 98 is 12 away; the nearest cube cell (95,95,95) is 75.
          assert_equal Color.palette(241), Color.rgb(100, 100, 100).quantize(:palette256)
        end

        it "prefers the cube for a saturated color" do
          assert_equal Color.palette(196), Color.rgb(255, 0, 0).quantize(:palette256)
        end

        it "maps the corners onto cube cells — the ramp reaches neither 0 nor 255" do
          assert_equal Color.palette(16), Color.rgb(0, 0, 0).quantize(:palette256)
          assert_equal Color.palette(231), Color.rgb(255, 255, 255).quantize(:palette256)
        end

        it "quantizes a background-derived tint — the case this exists for" do
          # A dark background stepped toward its own pole, as an app computing
          # a secondary-pane tint from Screen#background_color would produce.
          assert_equal Color.palette(234), Color.rgb(30, 30, 34).quantize(:palette256)
        end

        it "returns shared instances, so quantizing allocates nothing" do
          assert_same Color.rgb(95, 135, 175).quantize(:palette256),
                      Color.rgb(96, 135, 175).quantize(:palette256)
        end

        it "lands on a palette-valued color" do
          assert_kind_of Integer, Color.rgb(10, 20, 30).quantize(:palette256).value
        end
      end

      context "to the 16 named colors" do
        it "maps a palette cell onto the named color it matches" do
          assert_equal Color::BRIGHT_RED, Color.palette(196).quantize(:ansi16)
          assert_equal Color::BLACK, Color.palette(16).quantize(:ansi16)
        end

        it "maps a low palette index onto its own name, which 38;5 would not reach" do
          assert_equal Color::BRIGHT_RED, Color.palette(9).quantize(:ansi16)
        end

        it "maps RGB direct to the nearest of the 16, not via the palette" do
          # 195 is nearer 255 than 128, so bright_blue is right. Two-stepping
          # would round to cube cell 19 (0,0,175) first and then pick blue off
          # *that* — the compounded rounding this avoids.
          blue = Color.rgb(0, 0, 195)
          assert_equal Color::BRIGHT_BLUE, blue.quantize(:ansi16)
          assert_equal Color::BLUE, blue.quantize(:palette256).quantize(:ansi16)
        end

        it "lands on a named color, which still respects the terminal scheme" do
          assert_kind_of Symbol, Color.rgb(200, 10, 10).quantize(:ansi16).value
        end
      end

      it "raises on an unknown depth" do
        assert_raises(ArgumentError) { Color::RED.quantize(:monochrome) }
      end
    end

    describe "equality" do
      it "compares equal across forms" do
        assert_equal Color.new(:red), Color::RED
        assert_equal Color.new(42), Color.new(42)
        assert_equal Color.new([1, 2, 3]), Color.new([1, 2, 3])
      end

      it "differs across distinct values" do
        refute_equal Color::RED, Color::BLUE
        refute_equal Color.new(42), Color.new(43)
        refute_equal Color.new([1, 2, 3]), Color.new([1, 2, 4])
      end

      it "is not == to its raw value" do
        # Raw forms must round-trip through Color.coerce; direct equality with
        # the raw Symbol/Integer is intentionally false.
        refute_equal :red, Color::RED
      end

      it "has matching hash for equal Colors" do
        assert_equal Color.new(:red).hash, Color::RED.hash
        assert_equal Color.new(42).hash, Color.new(42).hash
      end

      it "supports use as a hash key" do
        h = { Color::RED => 1, Color::BLUE => 2 }
        assert_equal 1, h[Color.new(:red)]
        assert_equal 2, h[Color.new(:blue)]
      end
    end

    describe "#inspect" do
      it "shows the raw value" do
        assert_includes Color::RED.inspect, ":red"
        assert_includes Color.new(42).inspect, "42"
      end
    end
  end
end
