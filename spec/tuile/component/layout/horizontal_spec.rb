# frozen_string_literal: true

module Tuile
  describe Component::Layout::Horizontal do
    before { Screen.fake }
    after { Screen.close }

    def fixed(cells) = Component::Layout::Fixed[cells]
    def expand(weight) = Component::Layout::Expand[weight]

    # Every rect read below goes through this, so each settles first.
    def rects(layout)
      layout.flush_layout
      layout.children.map(&:rect)
    end

    def tops(layout) = rects(layout).map(&:top)
    def lefts(layout) = rects(layout).map(&:left)

    it "maps the main axis to width and the cross axis to height" do
      layout = Component::Layout::Horizontal.new
      layout.add(Component.new, fixed(3), cross: fixed(8))
      Testing.place(layout, Rect.new(0, 0, 20, 10))
      assert_equal Rect.new(0, 0, 3, 8), rects(layout).first
    end

    it "lays children out rightward" do
      layout = Component::Layout::Horizontal.new
      layout.add([Component.new, Component.new, Component.new], fixed(2))
      Testing.place(layout, Rect.new(5, 7, 20, 10))
      # The box's own coordinates: the children stack from its left edge, and
      # its position on screen is nowhere in their rects.
      assert_equal [0, 2, 4], lefts(layout)
      assert_equal [0, 0, 0], tops(layout)
      layout.flush_layout
      assert_equal([5, 7, 9], layout.children.map { |c| c.absolute_rect.left })
    end

    it "aligns :start to the top edge and :end to the bottom" do
      layout = Component::Layout::Horizontal.new
      layout.add(Component.new, fixed(1), cross: fixed(4), align: :start)
      layout.add(Component.new, fixed(1), cross: fixed(4), align: :end)
      Testing.place(layout, Rect.new(0, 0, 20, 10))
      assert_equal [0, 6], tops(layout)
    end

    # The sidebar-plus-content split, which is what Horizontal is for.
    it "gives a Fixed sidebar its columns and the rest to an Expand pane" do
      layout = Component::Layout::Horizontal.new
      sidebar = Component.new
      main = Component.new
      layout.add(sidebar, fixed(30))
      layout.add(main, expand(1))
      Testing.place(layout, Rect.new(0, 0, 100, 24))
      assert_equal [Rect.new(0, 0, 30, 24), Rect.new(30, 0, 70, 24)], rects(layout)
    end
  end

  describe Component::Layout::Horizontal, "#measure_rows" do
    before { Screen.fake }
    after { Screen.close }

    it "is the tallest shown Fixed cross height, plus the padding" do
      row = Component::Layout::Horizontal.new(padding: 1)
      row.add(Component::Label.new("a"), Component::Layout::Fixed[5], cross: Component::Layout::Fixed[1])
      tall = Component::Label.new("b")
      row.add(tall, Component::Layout::Fixed[5], cross: Component::Layout::Fixed[3])
      row.add(Component::Label.new("c"), Component::Layout::Expand[1])
      assert_equal 5, row.measure_rows(40)
      tall.visible = false
      assert_equal 3, row.measure_rows(40)
    end

    it "fills when every shown child is Percent across" do
      row = Component::Layout::Horizontal.new
      row.add(Component::Label.new("a"), Component::Layout::Expand[1])
      assert_nil row.measure_rows(40)
    end

    it "answers its padding with nothing shown" do
      assert_equal 2, Component::Layout::Horizontal.new(padding: 1).measure_rows(40)
    end

    it "asks an Auto child across at the share the row's division hands it" do
      row = Component::Layout::Horizontal.new(spacing: 1)
      row.add(Component::Label.new("a long sentence", wrap: true), Component::Layout::Expand[1],
              cross: Component::Layout::Auto[])
      row.add(Component::Button.new("Fix"), Component::Layout::Fixed[7], cross: Component::Layout::Fixed[1])
      assert_equal 3, row.measure_rows(14) # 6 columns for the sentence
      assert_equal 1, row.measure_rows(40)
    end
  end

  describe Component::Layout::Horizontal, "with Auto across" do
    before { Screen.fake }
    after { Screen.close }

    def auto = Component::Layout::Auto[]

    it "gives the child the rows it answers at its main share, aligned" do
      label = Component::Label.new("a long sentence", wrap: true)
      row = Component::Layout::Horizontal.new
      row.add(label, Component::Layout::Fixed[6], cross: auto, align: :end)
      mount_at(row, Rect.new(0, 0, 20, 5))
      assert_equal Rect.new(0, 2, 6, 3), label.rect
    end

    it "re-runs the pass when the child's rows change" do
      label = Component::Label.new("one")
      row = Component::Layout::Horizontal.new
      row.add(label, Component::Layout::Fixed[6], cross: auto)
      mount_at(row, Rect.new(0, 0, 20, 5))
      label.text = "one\ntwo"
      Testing.loop
      assert_equal 2, label.rect.height
    end

    it "raises on the main axis, where it would need a width from the child" do
      error = assert_raises(ArgumentError) { Component::Layout::Horizontal.new.add(Component.new, auto) }
      assert_match(/widths never do/, error.message)
    end
  end
end
