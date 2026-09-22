# frozen_string_literal: true

module Tuile
  describe Component::Layout::Absolute do
    before { Screen.fake }
    after { Screen.close }

    def rects(layout)
      layout.flush_layout
      layout.children.map(&:rect)
    end

    it "places each child at the rect it was added with" do
      layout = Component::Layout::Absolute.new
      layout.add(Component.new, Rect.new(0, 0, 10, 1))
      layout.add(Component.new, Rect.new(2, 3, 5, 4))
      assert_equal [Rect.new(0, 0, 10, 1), Rect.new(2, 3, 5, 4)], rects(layout)
    end

    # What makes a bare one the holder for measuring a tree with no screen.
    it "places its children whatever its own size, even with none" do
      layout = Component::Layout::Absolute.new
      layout.add(Component.new, Rect.new(1, 1, 8, 2))
      assert layout.rect.empty?
      assert_equal [Rect.new(1, 1, 8, 2)], rects(layout)
      Testing.place(layout, Rect.new(0, 0, 40, 20))
      assert_equal [Rect.new(1, 1, 8, 2)], rects(layout)
    end

    it "leaves a child added without a rect empty until it is constrained" do
      layout = Component::Layout::Absolute.new
      child = Component.new
      layout.add(child)
      layout.flush_layout
      assert layout.children.first.rect.empty?
      layout.constrain(child, Rect.new(0, 0, 10, 1))
      assert_equal [Rect.new(0, 0, 10, 1)], rects(layout)
    end

    describe "#constrain" do
      it "moves the child on the next settle, not before" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        layout.add(child, Rect.new(0, 0, 10, 1))
        layout.flush_layout
        layout.constrain(child, Rect.new(0, 5, 10, 1))
        assert_equal(Rect.new(0, 0, 10, 1), Tuile.without_strict_layout { child.rect })
        assert_equal [Rect.new(0, 5, 10, 1)], rects(layout)
      end

      it "marks nothing when the rect is the one it already has" do
        layout = Component::Layout::Absolute.new
        child = Component.new
        layout.add(child, Rect.new(0, 0, 10, 1))
        layout.flush_layout
        layout.constrain(child, Rect.new(0, 0, 10, 1))
        assert !layout.__send__(:layout_dirty?)
      end

      it "refuses a component that isn't its child" do
        layout = Component::Layout::Absolute.new
        assert_raises(ArgumentError) { layout.constrain(Component.new, Rect.new(0, 0, 1, 1)) }
      end
    end

    it "refuses anything but a Rect" do
      layout = Component::Layout::Absolute.new
      assert_raises(TypeError) { layout.add(Component.new, [0, 0, 1, 1]) }
      assert_empty layout.children
    end

    it "forgets a removed child's rect, so it can be re-added elsewhere" do
      layout = Component::Layout::Absolute.new
      child = Component.new
      layout.add(child, Rect.new(0, 0, 10, 1))
      layout.remove(child)
      layout.add(child, Rect.new(3, 3, 2, 2))
      assert_equal [Rect.new(3, 3, 2, 2)], rects(layout)
    end
  end
end
