# frozen_string_literal: true

module Tuile
  describe Component::Layout::Horizontal do
    before { Screen.fake }
    after { Screen.close }

    def fixed(cells) = Component::Layout::Fixed[cells]
    def expand(weight) = Component::Layout::Expand[weight]

    def tops(layout) = layout.children.map { |c| c.rect.top }
    def lefts(layout) = layout.children.map { |c| c.rect.left }

    it "maps the main axis to width and the cross axis to height" do
      layout = Component::Layout::Horizontal.new
      layout.add(Component.new, fixed(3), cross: fixed(8))
      layout.rect = Rect.new(0, 0, 20, 10)
      assert_equal Rect.new(0, 0, 3, 8), layout.children.first.rect
    end

    it "lays children out rightward" do
      layout = Component::Layout::Horizontal.new
      layout.add([Component.new, Component.new, Component.new], fixed(2))
      layout.rect = Rect.new(5, 7, 20, 10)
      assert_equal [5, 7, 9], lefts(layout)
      assert_equal [7, 7, 7], tops(layout)
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
      assert_equal Rect.new(0, 0, 30, 24), sidebar.rect
      assert_equal Rect.new(30, 0, 70, 24), main.rect
    end
  end
end
