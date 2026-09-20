# frozen_string_literal: true

module Tuile
  describe Canvas do
    before { Screen.fake }
    after { Screen.close }

    let(:buffer) { Screen.instance.buffer }

    it "refuses a backend that does not include Canvas::Backend" do
      assert_raises(Error) { Canvas.new(Object.new) }
    end

    it "paints into the buffer it was built over" do
      Canvas.new(buffer).set_text(0, 0, StyledString.plain("hi"))
      assert_equal "hi", buffer.region_text(Rect.new(0, 0, 2, 1)).first
    end

    context "the background it carries" do
      it "fills behind spans that state none" do
        Canvas.new(buffer, bg_color: Color.new(52)).set_text(0, 0, StyledString.plain("hi"))
        assert_equal Color.new(52), buffer.cell(0, 0).style.bg
      end

      it "leaves an explicit span bg untouched" do
        Canvas.new(buffer, bg_color: Color.new(52)).set_text(0, 0, StyledString.styled("hi", bg: :red))
        assert_equal Color::RED, buffer.cell(0, 0).style.bg
      end

      it "fills behind a char whose style states none" do
        Canvas.new(buffer, bg_color: Color.new(52)).set_char(0, 0, "x")
        assert_equal Color.new(52), buffer.cell(0, 0).style.bg
      end

      it "blanks a fill to it" do
        Canvas.new(buffer, bg_color: Color.new(52)).fill(Rect.new(0, 0, 2, 1))
        assert_equal Color.new(52), buffer.cell(0, 0).style.bg
      end

      # nil is the terminal default, never "inherit": inheritance is resolved
      # before the canvas is built.
      it "leaves the terminal default showing when nil" do
        Canvas.new(buffer).set_text(0, 0, StyledString.plain("hi"))
        assert_nil buffer.cell(0, 0).style.bg
      end
    end

    context "the origin it paints at" do
      it "defaults to the backend's own (0, 0)" do
        assert_equal Point.new(0, 0), Canvas.new(buffer).origin
      end

      it "offsets a set_text" do
        Canvas.new(buffer, origin: Point.new(3, 2)).set_text(1, 1, StyledString.plain("hi"))
        assert_equal "hi", buffer.region_text(Rect.new(4, 3, 2, 1)).first
      end

      it "offsets a set_char" do
        Canvas.new(buffer, origin: Point.new(3, 2)).set_char(1, 1, "x")
        assert_equal "x", buffer.cell(4, 3).grapheme
      end

      it "offsets a fill" do
        Canvas.new(buffer, origin: Point.new(3, 2), bg_color: Color.new(52)).fill(Rect.new(1, 1, 1, 1))
        assert_equal Color.new(52), buffer.cell(4, 3).style.bg
        assert_nil buffer.cell(1, 1).style.bg
      end

      # The terminal-edge clip belongs to the backend, so a negative origin —
      # as a scrolled child's would be — drops those rows rather than wrapping
      # them round or raising.
      it "leaves an out-of-range write for the backend to drop" do
        canvas = Canvas.new(buffer, origin: Point.new(0, -2))
        canvas.set_text(0, 2, StyledString.plain("kept")) # row 0
        canvas.set_text(0, 0, StyledString.plain("cut")) # row -2, dropped
        assert_equal "kept", buffer.region_text(Rect.new(0, 0, 4, 1)).first
      end
    end

    context "#with" do
      it "yields a canvas over the same backend at the new background" do
        canvas = Canvas.new(buffer, bg_color: Color.new(52))
        canvas.with(bg_color: Color.new(22)) { _1.fill(Rect.new(0, 0, 1, 1)) }
        assert_equal Color.new(22), buffer.cell(0, 0).style.bg
      end

      # The whole point of the shape: there is no state to restore, because the
      # receiver never changed.
      it "leaves the receiver untouched" do
        canvas = Canvas.new(buffer, bg_color: Color.new(52))
        canvas.with(bg_color: Color.new(22)) { _1 }
        canvas.fill(Rect.new(0, 0, 1, 1))
        assert_equal Color.new(52), buffer.cell(0, 0).style.bg
      end

      it "returns the block's value" do
        assert_equal 7, Canvas.new(buffer).with(bg_color: nil) { 7 }
      end

      it "hands back the receiver when the background is unchanged" do
        canvas = Canvas.new(buffer, bg_color: Color.new(52))
        assert_same canvas, canvas.with(bg_color: Color.new(52)) { _1 }
      end

      # Dropping the origin here would move every gap-clearing fill in the
      # default #repaint back to the screen's top-left, silently.
      it "carries the origin into the derived canvas" do
        canvas = Canvas.new(buffer, bg_color: Color.new(52), origin: Point.new(3, 2))
        canvas.with(bg_color: Color.new(22)) { _1.fill(Rect.new(1, 1, 1, 1)) }
        assert_equal Color.new(22), buffer.cell(4, 3).style.bg
      end

      # A derived canvas nobody scoped is exactly the dangling paint state this
      # shape exists to make unreachable.
      it "refuses to hand one out without a block" do
        assert_raises(Error) { Canvas.new(buffer).with(bg_color: nil) }
      end
    end

    it "is frozen, so nothing can change a canvas under whoever holds it" do
      assert_predicate Canvas.new(buffer), :frozen?
    end

    # The one mistake the mixed model makes possible, and it fails silently:
    # the write lands at twice the offset, in the component's *neighbour*,
    # where its own spec never looks. No allowlist — a {Canvas::Backend} does
    # its arithmetic on its own lines, and every widget in `lib/` paints
    # relative. A call split across lines slips through, so this is a tripwire
    # rather than a proof. See `D_canvas`.
    it "keeps screen coordinates out of every paint call site in lib/" do
      banned = [
        /\b(?:set_text|set_char|fill)\(.*\brect\.(?:left|top)\b/,
        /\.fill\((?:rect|extent_rect)\)/
      ].freeze
      lib = File.expand_path("../../lib", __dir__)
      offenders = Dir["#{lib}/**/*.rb"].sort.flat_map do |path|
        File.readlines(path).each_with_index.filter_map do |text, i|
          "#{path.delete_prefix("#{lib}/")}:#{i + 1}:#{text.strip}" if banned.any? { text.match?(_1) }
        end
      end

      assert_empty offenders,
                   "a canvas paints in the component's own coordinates — pass local_rect, " \
                   "not rect; see D_canvas:\n  #{offenders.join("\n  ")}"
    end
  end

  describe Canvas::Backend do
    before { Screen.fake }
    after { Screen.close }

    # The module is the protocol and nothing else: an implementation that
    # forgets one of the three fails loudly the first time a component paints,
    # rather than silently dropping every cell that method would have written.
    it "raises until an includer implements each of the three" do
      backend = Class.new { include Canvas::Backend }.new
      assert_raises(NotImplementedError) { backend.set_text(0, 0, StyledString.plain("x")) }
      assert_raises(NotImplementedError) { backend.set_char(0, 0, "x", StyledString::Style::DEFAULT) }
      assert_raises(NotImplementedError) { backend.fill(Rect.new(0, 0, 1, 1), StyledString::Style::DEFAULT) }
    end

    it "is satisfied by Buffer with no adapter" do
      assert_kind_of Canvas::Backend, Screen.instance.buffer
    end
  end
end
