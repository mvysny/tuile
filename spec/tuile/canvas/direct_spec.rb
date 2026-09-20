# frozen_string_literal: true

module Tuile
  describe Canvas::Direct do
    let(:buffer) { Buffer.new(Size.new(10, 3)) }
    let(:canvas) { Canvas::Direct.new(buffer) }

    it "writes text into the buffer" do
      canvas.set_text(2, 1, StyledString.plain("hi"))
      assert_equal ["hi"], buffer.region_text(Rect.new(2, 1, 2, 1))
    end

    it "writes a grapheme into the buffer" do
      canvas.set_char(0, 0, "x")
      assert_equal "x", buffer.cell(0, 0).grapheme
    end

    it "fills a rect in the buffer" do
      canvas.set_char(1, 0, "x")
      canvas.fill(Rect.new(0, 0, 10, 1))
      assert_equal " ", buffer.cell(1, 0).grapheme
    end

    # The buffer is held, not its geometry: Screen#layout resizes the one buffer
    # in place on every SIGWINCH, and building a new canvas for each would be a
    # second thing to remember.
    it "keeps painting after the buffer is resized" do
      buffer.resize(Size.new(40, 5))
      canvas.set_text(30, 4, StyledString.plain("wide"))
      assert_equal ["wide"], buffer.region_text(Rect.new(30, 4, 4, 1))
    end
  end
end
