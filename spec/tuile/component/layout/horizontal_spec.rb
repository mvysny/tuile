# frozen_string_literal: true

module Tuile
  describe Component::Layout::Horizontal do
    before { Screen.fake }
    after { Screen.close }

    def fixed(cells) = Component::Layout::Fixed[cells]
    def expand(weight) = Component::Layout::Expand[weight]

    # Every rect read below goes through this, so each settles first.
    def rects(layout) = settle(layout).children.map(&:rect)
    def tops(layout) = rects(layout).map(&:top)
    def lefts(layout) = rects(layout).map(&:left)

    it "maps the main axis to width and the cross axis to height" do
      layout = Component::Layout::Horizontal.new
      layout.add(Component.new, fixed(3), cross: fixed(8))
      layout.rect = Rect.new(0, 0, 20, 10)
      assert_equal Rect.new(0, 0, 3, 8), rects(layout).first
    end

    it "lays children out rightward" do
      layout = Component::Layout::Horizontal.new
      layout.add([Component.new, Component.new, Component.new], fixed(2))
      layout.rect = Rect.new(5, 7, 20, 10)
      # The box's own coordinates: the children stack from its left edge, and
      # its position on screen is nowhere in their rects.
      assert_equal [0, 2, 4], lefts(layout)
      assert_equal [0, 0, 0], tops(layout)
      settle(layout)
      assert_equal([5, 7, 9], layout.children.map { |c| c.absolute_rect.left })
    end

    it "aligns :start to the top edge and :end to the bottom" do
      layout = Component::Layout::Horizontal.new
      layout.add(Component.new, fixed(1), cross: fixed(4), align: :start)
      layout.add(Component.new, fixed(1), cross: fixed(4), align: :end)
      layout.rect = Rect.new(0, 0, 20, 10)
      assert_equal [0, 6], tops(layout)
    end

    # The sidebar-plus-content split, which is what Horizontal is for.
    it "gives a Fixed sidebar its columns and the rest to an Expand pane" do
      layout = Component::Layout::Horizontal.new
      sidebar = Component.new
      main = Component.new
      layout.add(sidebar, fixed(30))
      layout.add(main, expand(1))
      layout.rect = Rect.new(0, 0, 100, 24)
      assert_equal [Rect.new(0, 0, 30, 24), Rect.new(30, 0, 70, 24)], rects(layout)
    end
  end
end
