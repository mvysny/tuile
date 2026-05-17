# frozen_string_literal: true

module Tuile
  describe StyledString do
    describe StyledString::Style do
      describe ".new" do
        it "defaults all attributes" do
          s = StyledString::Style.new
          assert_nil s.fg
          assert_nil s.bg
          refute s.bold
          refute s.italic
          refute s.underline
        end

        it "accepts symbolic colors" do
          s = StyledString::Style.new(fg: :red, bg: :bright_blue)
          assert_equal :red, s.fg
          assert_equal :bright_blue, s.bg
        end

        it "accepts 256-color integers" do
          s = StyledString::Style.new(fg: 42)
          assert_equal 42, s.fg
        end

        it "accepts RGB triples" do
          s = StyledString::Style.new(fg: [255, 100, 0])
          assert_equal [255, 100, 0], s.fg
        end

        it "raises on unknown color symbol" do
          assert_raises(ArgumentError) { StyledString::Style.new(fg: :neon) }
        end

        it "raises on out-of-range 256-color" do
          assert_raises(ArgumentError) { StyledString::Style.new(fg: 256) }
          assert_raises(ArgumentError) { StyledString::Style.new(fg: -1) }
        end

        it "raises on malformed RGB triple" do
          assert_raises(ArgumentError) { StyledString::Style.new(fg: [255, 0]) }
          assert_raises(ArgumentError) { StyledString::Style.new(fg: [255, 0, 256]) }
          assert_raises(ArgumentError) { StyledString::Style.new(fg: [255, 0, "z"]) }
        end
      end

      describe "::DEFAULT" do
        it "is all-defaults" do
          assert StyledString::Style::DEFAULT.default?
        end

        it "compares equal to a fresh default" do
          assert_equal StyledString::Style::DEFAULT, StyledString::Style.new
        end
      end

      describe "#default?" do
        it "is true when no attributes set" do
          assert StyledString::Style.new.default?
        end

        it "is false when any attribute is non-default" do
          refute StyledString::Style.new(fg: :red).default?
          refute StyledString::Style.new(bold: true).default?
        end
      end

      describe "#merge" do
        it "returns a new Style with overrides applied" do
          base = StyledString::Style.new(fg: :red, bold: true)
          merged = base.merge(bold: false, italic: true)
          assert_equal :red, merged.fg
          refute merged.bold
          assert merged.italic
        end

        it "does not mutate the receiver" do
          base = StyledString::Style.new(fg: :red)
          base.merge(fg: :blue)
          assert_equal :red, base.fg
        end
      end

      describe "structural equality" do
        it "two styles with same attributes are ==" do
          a = StyledString::Style.new(fg: :red, bold: true)
          b = StyledString::Style.new(fg: :red, bold: true)
          assert_equal a, b
          assert_equal a.hash, b.hash
        end

        it "differing attributes are not ==" do
          refute_equal StyledString::Style.new(fg: :red), StyledString::Style.new(fg: :green)
        end
      end
    end

    describe StyledString::Span do
      it "exposes text and style" do
        s = StyledString::Style.new(fg: :red)
        span = StyledString::Span.new(text: "hi", style: s)
        assert_equal "hi", span.text
        assert_equal s, span.style
      end

      it "freezes text" do
        span = StyledString::Span.new(text: +"hi", style: StyledString::Style::DEFAULT)
        assert span.text.frozen?
      end

      it "raises when text is not a String" do
        assert_raises(ArgumentError) { StyledString::Span.new(text: 42, style: StyledString::Style::DEFAULT) }
      end

      it "raises when style is not a Style" do
        assert_raises(ArgumentError) { StyledString::Span.new(text: "x", style: :red) }
      end
    end

    describe ".plain" do
      it "returns an empty StyledString for empty input" do
        assert StyledString.plain("").empty?
      end

      it "returns a single default-styled span" do
        ss = StyledString.plain("hello")
        assert_equal 1, ss.spans.length
        assert_equal "hello", ss.spans[0].text
        assert ss.spans[0].style.default?
      end

      it "coerces via to_s" do
        assert_equal "42", StyledString.plain(42).to_s
      end
    end

    describe ".styled" do
      it "returns empty for empty input" do
        assert StyledString.styled("", fg: :red).empty?
      end

      it "builds a span with the given style" do
        ss = StyledString.styled("hi", fg: :red, bold: true)
        assert_equal "hi", ss.spans[0].text
        assert_equal :red, ss.spans[0].style.fg
        assert ss.spans[0].style.bold
      end
    end

    describe ".parse" do
      it "returns the same StyledString on idempotent input" do
        ss = StyledString.plain("hi")
        assert_same ss, StyledString.parse(ss)
      end

      it "returns empty for empty string" do
        assert StyledString.parse("").empty?
      end

      it "fast-paths plain strings (no ESC)" do
        ss = StyledString.parse("hello world")
        assert_equal 1, ss.spans.length
        assert ss.spans[0].style.default?
      end

      it "parses a single foreground color" do
        ss = StyledString.parse("\e[31mhi\e[0m")
        assert_equal 1, ss.spans.length
        assert_equal :red, ss.spans[0].style.fg
      end

      it "splits at SGR boundaries" do
        ss = StyledString.parse("\e[31mhello\e[0m world")
        assert_equal 2, ss.spans.length
        assert_equal "hello", ss.spans[0].text
        assert_equal :red, ss.spans[0].style.fg
        assert_equal " world", ss.spans[1].text
        assert ss.spans[1].style.default?
      end

      it "parses multiple codes in one SGR" do
        ss = StyledString.parse("\e[1;31mx\e[0m")
        assert ss.spans[0].style.bold
        assert_equal :red, ss.spans[0].style.fg
      end

      it "parses bg colors" do
        ss = StyledString.parse("\e[41mx\e[0m")
        assert_equal :red, ss.spans[0].style.bg
      end

      it "parses bright fg" do
        ss = StyledString.parse("\e[91mx\e[0m")
        assert_equal :bright_red, ss.spans[0].style.fg
      end

      it "parses bright bg" do
        ss = StyledString.parse("\e[101mx\e[0m")
        assert_equal :bright_red, ss.spans[0].style.bg
      end

      it "parses 256-color fg" do
        ss = StyledString.parse("\e[38;5;42mx\e[0m")
        assert_equal 42, ss.spans[0].style.fg
      end

      it "parses 256-color bg" do
        ss = StyledString.parse("\e[48;5;200mx\e[0m")
        assert_equal 200, ss.spans[0].style.bg
      end

      it "parses RGB fg" do
        ss = StyledString.parse("\e[38;2;255;100;0mx\e[0m")
        assert_equal [255, 100, 0], ss.spans[0].style.fg
      end

      it "parses RGB bg" do
        ss = StyledString.parse("\e[48;2;0;0;0mx\e[0m")
        assert_equal [0, 0, 0], ss.spans[0].style.bg
      end

      it "treats \\e[m as reset" do
        ss = StyledString.parse("\e[31mhi\e[mworld")
        assert_equal :red, ss.spans[0].style.fg
        assert ss.spans[1].style.default?
      end

      it "handles attribute toggles (bold on/off)" do
        ss = StyledString.parse("\e[1ma\e[22mb")
        assert ss.spans[0].style.bold
        refute ss.spans[1].style.bold
      end

      it "handles fg-default 39" do
        ss = StyledString.parse("\e[31ma\e[39mb")
        assert_equal :red, ss.spans[0].style.fg
        assert_nil ss.spans[1].style.fg
      end

      it "handles bg-default 49" do
        ss = StyledString.parse("\e[41ma\e[49mb")
        assert_equal :red, ss.spans[0].style.bg
        assert_nil ss.spans[1].style.bg
      end

      it "accumulates attributes across SGRs" do
        ss = StyledString.parse("\e[31m\e[1mx\e[0m")
        assert_equal :red, ss.spans[0].style.fg
        assert ss.spans[0].style.bold
      end

      describe "strict raise contract" do
        {
          "dim (2)" => "\e[2mx",
          "blink (5)" => "\e[5mx",
          "rapid blink (6)" => "\e[6mx",
          "reverse (7)" => "\e[7mx",
          "conceal (8)" => "\e[8mx",
          "strike (9)" => "\e[9mx",
          "double-underline (21)" => "\e[21mx",
          "blink off (25)" => "\e[25mx",
          "reverse off (27)" => "\e[27mx",
          "strike off (29)" => "\e[29mx",
          "overline (53)" => "\e[53mx",
          "unknown code (99)" => "\e[99mx"
        }.each do |label, input|
          it "raises on unmodeled SGR: #{label}" do
            assert_raises(StyledString::ParseError) { StyledString.parse(input) }
          end
        end

        it "raises on non-SGR CSI (clear line)" do
          assert_raises(StyledString::ParseError) { StyledString.parse("\e[2Khello") }
        end

        it "raises on cursor move" do
          assert_raises(StyledString::ParseError) { StyledString.parse("\e[10;20Hhello") }
        end

        it "raises on non-CSI escape" do
          assert_raises(StyledString::ParseError) { StyledString.parse("\eX") }
        end

        it "raises on truncated escape" do
          assert_raises(StyledString::ParseError) { StyledString.parse("\e[31") }
        end

        it "raises on 256-color out of range" do
          assert_raises(StyledString::ParseError) { StyledString.parse("\e[38;5;300mx") }
        end

        it "raises on RGB short triple" do
          assert_raises(StyledString::ParseError) { StyledString.parse("\e[38;2;255;100mx") }
        end

        it "raises on unknown extended-color selector" do
          assert_raises(StyledString::ParseError) { StyledString.parse("\e[38;9;1mx") }
        end
      end

      it "raises TypeError on non-string non-StyledString input" do
        assert_raises(TypeError) { StyledString.parse(42) }
      end
    end

    describe "normalization" do
      it "drops empty-text spans" do
        ss = StyledString.new([
                                StyledString::Span.new(text: "", style: StyledString::Style::DEFAULT),
                                StyledString::Span.new(text: "x", style: StyledString::Style::DEFAULT)
                              ])
        assert_equal 1, ss.spans.length
        assert_equal "x", ss.spans[0].text
      end

      it "merges adjacent same-style spans" do
        style = StyledString::Style.new(fg: :red)
        ss = StyledString.new([
                                StyledString::Span.new(text: "ab", style: style),
                                StyledString::Span.new(text: "cd", style: style)
                              ])
        assert_equal 1, ss.spans.length
        assert_equal "abcd", ss.spans[0].text
      end

      it "freezes the spans array" do
        ss = StyledString.plain("hi")
        assert ss.spans.frozen?
      end
    end

    describe "#display_width" do
      it "is zero for empty" do
        assert_equal 0, StyledString.new.display_width
      end

      it "counts ASCII as one column each" do
        assert_equal 5, StyledString.plain("hello").display_width
      end

      it "counts CJK characters as two columns each" do
        assert_equal 4, StyledString.plain("中国").display_width
      end

      it "sums across spans" do
        ss = StyledString.parse("\e[31mhello\e[0m world")
        assert_equal 11, ss.display_width
      end
    end

    describe "#empty?" do
      it "is true on empty" do
        assert StyledString.new.empty?
      end

      it "is false when there's content" do
        refute StyledString.plain("x").empty?
      end
    end

    describe "#to_s" do
      it "returns plain text with no SGR" do
        ss = StyledString.parse("\e[31mhello\e[0m world")
        assert_equal "hello world", ss.to_s
      end

      it "returns empty string for empty" do
        assert_equal "", StyledString.new.to_s
      end
    end

    describe "#to_ansi" do
      it "is empty for an empty StyledString" do
        assert_equal "", StyledString.new.to_ansi
      end

      it "emits plain text with no SGR when default-styled" do
        assert_equal "hello", StyledString.plain("hello").to_ansi
      end

      it "wraps a styled run with SGR and closing reset" do
        assert_equal "\e[31mhello\e[0m", StyledString.styled("hello", fg: :red).to_ansi
      end

      it "transitions to default with \\e[0m" do
        ss = StyledString.parse("\e[31mhello\e[0m world")
        assert_equal "\e[31mhello\e[0m world", ss.to_ansi
      end

      it "emits minimal diff between adjacent spans (turns off bold only)" do
        red_bold = StyledString::Style.new(fg: :red, bold: true)
        red = StyledString::Style.new(fg: :red)
        ss = StyledString.new([
                                StyledString::Span.new(text: "a", style: red_bold),
                                StyledString::Span.new(text: "b", style: red)
                              ])
        # going from red+bold to red: only bold-off (22) is emitted
        assert_equal "\e[1;31ma\e[22mb\e[0m", ss.to_ansi
      end

      it "emits minimal diff (changes fg only)" do
        ss = StyledString.new([
                                StyledString::Span.new(text: "a", style: StyledString::Style.new(fg: :red)),
                                StyledString::Span.new(text: "b", style: StyledString::Style.new(fg: :green))
                              ])
        assert_equal "\e[31ma\e[32mb\e[0m", ss.to_ansi
      end

      it "emits 256-color SGR" do
        assert_equal "\e[38;5;42mx\e[0m", StyledString.styled("x", fg: 42).to_ansi
      end

      it "emits RGB SGR" do
        assert_equal "\e[38;2;255;100;0mx\e[0m", StyledString.styled("x", fg: [255, 100, 0]).to_ansi
      end

      it "emits bright fg" do
        assert_equal "\e[91mx\e[0m", StyledString.styled("x", fg: :bright_red).to_ansi
      end

      it "emits bg SGR" do
        assert_equal "\e[41mx\e[0m", StyledString.styled("x", bg: :red).to_ansi
      end

      it "emits italic + underline + bold combined" do
        ss = StyledString.styled("x", bold: true, italic: true, underline: true)
        # order: bold(1), italic(3), underline(4)
        assert_equal "\e[1;3;4mx\e[0m", ss.to_ansi
      end

      it "does not emit a trailing reset when the last span is default" do
        ss = StyledString.parse("\e[31ma\e[0mb")
        assert_equal "\e[31ma\e[0mb", ss.to_ansi
      end

      it "memoizes the rendered string" do
        ss = StyledString.styled("hello", fg: :red)
        assert_same ss.to_ansi, ss.to_ansi
      end
    end

    describe "equality" do
      it "is == when spans match" do
        assert_equal StyledString.plain("hi"), StyledString.plain("hi")
      end

      it "is not == across different content" do
        refute_equal StyledString.plain("hi"), StyledString.plain("bye")
      end

      it "is not == across different styles" do
        refute_equal StyledString.plain("hi"), StyledString.styled("hi", fg: :red)
      end

      it "has matching hash for equal values" do
        assert_equal StyledString.plain("hi").hash, StyledString.plain("hi").hash
      end

      it "is not == to non-StyledString values" do
        refute_equal StyledString.plain("hi"), "hi"
      end
    end

    describe "#+" do
      it "concatenates two StyledStrings" do
        result = StyledString.plain("a") + StyledString.plain("b")
        assert_equal "ab", result.to_s
      end

      it "coerces a String operand via .parse" do
        styled = StyledString.styled("a", fg: :red)
        result = styled + "b" # rubocop:disable Style/StringConcatenation -- StyledString#+, not String#+
        assert_equal "ab", result.to_s
        assert_equal :red, result.spans[0].style.fg
        assert result.spans[1].style.default?
      end

      it "parses ANSI in a String operand" do
        plain = StyledString.plain("a")
        result = plain + "\e[31mb\e[0m" # rubocop:disable Style/StringConcatenation -- StyledString#+, not String#+
        assert_equal "ab", result.to_s
        assert_equal :red, result.spans[1].style.fg
      end

      it "merges adjacent same-style spans across the join" do
        red = StyledString.styled("a", fg: :red)
        more_red = StyledString.styled("b", fg: :red)
        joined = red + more_red
        assert_equal 1, joined.spans.length
        assert_equal "ab", joined.spans[0].text
      end

      it "raises TypeError on bad operand" do
        assert_raises(TypeError) { StyledString.plain("a") + 42 }
      end
    end

    describe "#slice" do
      let(:ss) { StyledString.parse("\e[31mhello\e[0m world") }

      it "returns empty for negative length" do
        assert StyledString.plain("hello").slice(0, -1).empty?
      end

      it "returns empty for zero length" do
        assert StyledString.plain("hello").slice(0, 0).empty?
      end

      it "returns empty when start is beyond width" do
        assert StyledString.plain("hello").slice(100, 5).empty?
      end

      it "slices within a single span" do
        sliced = ss.slice(0, 3)
        assert_equal "hel", sliced.to_s
        assert_equal :red, sliced.spans[0].style.fg
      end

      it "slices across spans, preserving each span's style" do
        sliced = ss.slice(3, 5) # "lo wo"
        assert_equal "lo wo", sliced.to_s
        assert_equal :red, sliced.spans[0].style.fg
        assert_equal "lo", sliced.spans[0].text
        assert_equal " wo", sliced.spans[1].text
      end

      it "accepts a Range with inclusive end" do
        sliced = ss.slice(0..4)
        assert_equal "hello", sliced.to_s
      end

      it "accepts a Range with exclusive end" do
        sliced = ss.slice(0...5)
        assert_equal "hello", sliced.to_s
      end

      it "accepts an endless Range" do
        sliced = ss.slice(6..)
        assert_equal "world", sliced.to_s
      end

      it "accepts a beginless Range" do
        sliced = ss.slice(..4)
        assert_equal "hello", sliced.to_s
      end

      it "accepts negative start" do
        sliced = ss.slice(-5, 5)
        assert_equal "world", sliced.to_s
      end

      it "accepts negative range bounds" do
        sliced = ss.slice(-5..-1)
        assert_equal "world", sliced.to_s
      end

      it "clamps length to remaining width" do
        sliced = ss.slice(8, 100)
        assert_equal "rld", sliced.to_s
      end

      it "drops a wide character that straddles the start boundary" do
        # "中abc": cols 0-1 = 中, 2 = a, 3 = b, 4 = c
        ss = StyledString.plain("中abc")
        sliced = ss.slice(1, 3) # cols 1, 2, 3 — col 1 is inside 中, dropped
        assert_equal "ab", sliced.to_s
      end

      it "drops a wide character that straddles the end boundary" do
        ss = StyledString.plain("ab中")
        sliced = ss.slice(0, 3) # cols 0, 1, 2 — col 2 is inside 中, dropped
        assert_equal "ab", sliced.to_s
      end

      it "includes wide characters fully inside the slice" do
        ss = StyledString.plain("中国")
        sliced = ss.slice(0, 4)
        assert_equal "中国", sliced.to_s
      end

      it "requires a length when given an Integer start" do
        assert_raises(ArgumentError) { StyledString.plain("hi").slice(0) }
      end
    end

    describe "#lines" do
      it "returns [empty] for an empty StyledString" do
        result = StyledString.new.lines
        assert_equal 1, result.length
        assert result[0].empty?
      end

      it "returns a single line for newline-free input" do
        result = StyledString.plain("hello").lines
        assert_equal 1, result.length
        assert_equal "hello", result[0].to_s
      end

      it "splits on a single newline" do
        result = StyledString.plain("a\nb").lines
        assert_equal 2, result.length
        assert_equal "a", result[0].to_s
        assert_equal "b", result[1].to_s
      end

      it "preserves trailing empty line" do
        result = StyledString.plain("a\n").lines
        assert_equal 2, result.length
        assert_equal "a", result[0].to_s
        assert result[1].empty?
      end

      it "preserves consecutive blank lines" do
        result = StyledString.plain("a\n\nb").lines
        assert_equal 3, result.length
        assert_equal "a", result[0].to_s
        assert result[1].empty?
        assert_equal "b", result[2].to_s
      end

      it "preserves style on each side of a newline" do
        ss = StyledString.styled("a\nb", fg: :red)
        lines = ss.lines
        assert_equal 2, lines.length
        assert_equal :red, lines[0].spans[0].style.fg
        assert_equal :red, lines[1].spans[0].style.fg
      end

      it "splits a span that crosses a newline boundary into both lines" do
        ss = StyledString.styled("hello\nworld", fg: :red)
        lines = ss.lines
        assert_equal "hello", lines[0].to_s
        assert_equal "world", lines[1].to_s
      end
    end

    describe "#each_char_with_style" do
      it "yields each character with its style" do
        ss = StyledString.parse("\e[31mab\e[0mc")
        collected = []
        ss.each_char_with_style { |c, s| collected << [c, s] }
        assert_equal 3, collected.length
        assert_equal "a", collected[0][0]
        assert_equal :red, collected[0][1].fg
        assert_equal "b", collected[1][0]
        assert_equal :red, collected[1][1].fg
        assert_equal "c", collected[2][0]
        assert collected[2][1].default?
      end

      it "returns an Enumerator without a block" do
        ss = StyledString.plain("hi")
        e = ss.each_char_with_style
        assert e.is_a?(Enumerator)
        assert_equal [["h", StyledString::Style::DEFAULT], ["i", StyledString::Style::DEFAULT]], e.to_a
      end
    end

    describe "#inspect" do
      it "shows the plain text" do
        assert_includes StyledString.styled("hi", fg: :red).inspect, '"hi"'
      end
    end

    describe "round-trip parse ↔ to_ansi" do
      [
        "",
        "hello",
        "\e[31mhello\e[0m",
        "\e[31mhello\e[0m world",
        "\e[1;31mhi\e[0m",
        "\e[38;5;42mhi\e[0m",
        "\e[38;2;255;100;0mhi\e[0m",
        "\e[91mhi\e[0m",
        "\e[41mhi\e[0m"
      ].each do |input|
        it "preserves #{input.inspect}" do
          parsed = StyledString.parse(input)
          reparsed = StyledString.parse(parsed.to_ansi)
          assert_equal parsed, reparsed
        end
      end
    end
  end
end
