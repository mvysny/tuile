# frozen_string_literal: true

module Tuile
  describe Component::Layout::Vertical do
    before { Screen.fake }
    after { Screen.close }

    def fixed(cells) = Component::Layout::Fixed[cells]
    def expand(weight) = Component::Layout::Expand[weight]

    # Every rect read below goes through this, so each settles first.
    def rects(layout)
      layout.flush_layout
      layout.children.map(&:rect)
    end

    def heights(layout) = rects(layout).map(&:height)
    def tops(layout) = rects(layout).map(&:top)
    def lefts(layout) = rects(layout).map(&:left)

    it "maps the main axis to height and the cross axis to width" do
      layout = Component::Layout::Vertical.new
      layout.add(Component.new, fixed(3), cross: fixed(8))
      Testing.place(layout, Rect.new(0, 0, 20, 10))
      assert_equal Rect.new(0, 0, 8, 3), rects(layout).first
    end

    it "stacks children downward" do
      layout = Component::Layout::Vertical.new
      layout.add([Component.new, Component.new, Component.new], fixed(2))
      Testing.place(layout, Rect.new(5, 7, 20, 10))
      # The box's own coordinates: the children stack from its top edge, and
      # its position on screen is nowhere in their rects.
      assert_equal [0, 2, 4], tops(layout)
      assert_equal [0, 0, 0], lefts(layout)
      layout.flush_layout
      assert_equal([7, 9, 11], layout.children.map { |c| c.absolute_rect.top })
    end

    it "aligns :start to the left edge and :end to the right" do
      layout = Component::Layout::Vertical.new
      layout.add(Component.new, fixed(1), cross: fixed(4), align: :start)
      layout.add(Component.new, fixed(1), cross: fixed(4), align: :end)
      Testing.place(layout, Rect.new(0, 0, 20, 10))
      assert_equal [0, 16], lefts(layout)
    end

    it "recomputes on resize" do
      layout = Component::Layout::Vertical.new
      layout.add(Component.new, fixed(2))
      layout.add(Component.new, expand(1))
      Testing.place(layout, Rect.new(0, 0, 20, 10))
      assert_equal [2, 8], heights(layout)
      Testing.place(layout, Rect.new(0, 0, 20, 20))
      assert_equal [2, 18], heights(layout)
    end

    it "paints a child's content at the rect it was given" do
      layout = Component::Layout::Vertical.new(spacing: 1)
      first = Component::Label.new
      first.text = "first"
      second = Component::Label.new
      second.text = "second"
      layout.add([first, second], fixed(1))
      mount_at(layout, Rect.new(0, 0, 10, 5))
      Screen.instance.repaint
      assert_equal ["first     ", "          ", "second    "],
                   Screen.instance.buffer.region_text(Rect.new(0, 0, 10, 3))
    end
  end

  describe Component::Layout::Vertical, "#measure_rows" do
    before { Screen.fake }
    after { Screen.close }

    it "sums the shown Fixed heights, the spacing and the padding" do
      box = Component::Layout::Vertical.new(spacing: 1, padding: 2)
      box.add(Component::Label.new("a"), Component::Layout::Fixed[1])
      hidden = Component::Label.new("b")
      box.add(hidden, Component::Layout::Fixed[5])
      box.add(Component::Label.new("c"), Component::Layout::Fixed[2])
      assert_equal 14, box.measure_rows(40)
      hidden.visible = false
      assert_equal 8, box.measure_rows(40)
    end

    it "fills when a shown child is a share of the height" do
      [Component::Layout::Expand[1], Component::Layout::Percent[50]].each do |share|
        box = Component::Layout::Vertical.new
        box.add(Component::Label.new("a"), Component::Layout::Fixed[1])
        box.add(Component::Label.new("b"), share)
        assert_nil box.measure_rows(40)
      end
    end

    it "answers its padding with nothing shown" do
      assert_equal 2, Component::Layout::Vertical.new(padding: 1).measure_rows(40)
    end
  end
end
