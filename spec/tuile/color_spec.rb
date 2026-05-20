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
