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

      # A derived canvas nobody scoped is exactly the dangling paint state this
      # shape exists to make unreachable.
      it "refuses to hand one out without a block" do
        assert_raises(Error) { Canvas.new(buffer).with(bg_color: nil) }
      end
    end

    it "is frozen, so nothing can change a canvas under whoever holds it" do
      assert_predicate Canvas.new(buffer), :frozen?
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
