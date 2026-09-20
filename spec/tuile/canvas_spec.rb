# frozen_string_literal: true

module Tuile
  describe Canvas do
    # The base class is the protocol and nothing else: a subclass that forgets
    # one of the three fails loudly the first time a component paints, rather
    # than silently dropping every cell that method would have written.
    it "is abstract — each of the three raises until a subclass implements it" do
      canvas = Canvas.new
      assert_raises(NotImplementedError) { canvas.set_text(0, 0, StyledString.plain("x")) }
      assert_raises(NotImplementedError) { canvas.set_char(0, 0, "x") }
      assert_raises(NotImplementedError) { canvas.fill(Rect.new(0, 0, 1, 1)) }
    end
  end
end
