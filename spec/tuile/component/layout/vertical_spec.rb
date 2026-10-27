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

    it "counts an Auto child's answer at the width its cross resolves to" do
      box = Component::Layout::Vertical.new(spacing: 1, padding: Component::Layout::Insets[left: 2])
      box.add(Component::Label.new("Title"), Component::Layout::Fixed[1])
      box.add(Component::Label.new("a long sentence", wrap: true), Component::Layout::Auto[])
      assert_equal 5, box.measure_rows(8) # 1 + gap + 3 rows at 6 columns
      box.constrain(box.children.last, cross: Component::Layout::Fixed[8])
      assert_equal 4, box.measure_rows(40) # 2 rows at 8
    end
  end

  describe Component::Layout::Vertical, "with Auto children" do
    before { Screen.fake }
    after { Screen.close }

    def auto = Component::Layout::Auto[]

    def paragraph(text = "a long sentence") = Component::Label.new(text, wrap: true)

    it "gives an Auto child the rows it answers at the width it is handed" do
      label = paragraph
      box = Component::Layout::Vertical.new
      box.add(label, auto, cross: Component::Layout::Fixed[6])
      box.add(rest = Component.new, Component::Layout::Expand[1])
      mount_at(box, Rect.new(0, 0, 20, 10))
      assert_equal Rect.new(0, 0, 6, 3), label.rect
      assert_equal Rect.new(0, 3, 20, 7), rest.rect
    end

    it "clamps the answer to what is left, like a Fixed" do
      label = paragraph
      box = Component::Layout::Vertical.new
      box.add(Component.new, Component::Layout::Fixed[4])
      box.add(label, auto, cross: Component::Layout::Fixed[6])
      mount_at(box, Rect.new(0, 0, 20, 5))
      assert_equal 1, label.rect.height
    end

    it "re-runs the pass when the child's rows change, and only then" do
      label = paragraph("short")
      fixed = Component::Label.new("fixed")
      box = Component::Layout::Vertical.new
      box.add(label, auto)
      box.add(fixed, Component::Layout::Fixed[1])
      mount_at(box, Rect.new(0, 0, 20, 10))
      fixed.text = "still one row"
      refute box.layout_dirty?, "a Fixed child's rows are read by nobody"
      label.text = "one\ntwo\nthree"
      Testing.loop
      assert_equal 3, label.rect.height
      assert_equal 3, fixed.rect.top
    end

    it "re-measures at the new width on resize" do
      label = paragraph("aaaa bbbb cccc")
      box = Component::Layout::Vertical.new
      box.add(label, auto)
      mount_at(box, Rect.new(0, 0, 14, 10))
      assert_equal 1, label.rect.height
      Testing.place(box, Rect.new(0, 0, 4, 10))
      box.flush_layout
      assert_equal 3, label.rect.height
    end

    it "gives a child answering nil no rows, and says so in the log" do
      previous = Tuile.logger
      io = StringIO.new
      Tuile.logger = Logger.new(io)
      body = Component.new
      box = Component::Layout::Vertical.new
      box.add(body, auto)
      mount_at(box, Rect.new(0, 0, 20, 10))
      assert_equal 0, body.rect.height
      assert_match(/answers measure_rows nil/, io.string)
    ensure
      Tuile.logger = previous
    end

    it "raises as cross:, where it would need a width from the child" do
      error = assert_raises(ArgumentError) do
        Component::Layout::Vertical.new.add(Component.new, Component::Layout::Fixed[1], cross: auto)
      end
      assert_match(/widths never do/, error.message)
      box = Component::Layout::Vertical.new
      box.add(child = Component.new)
      assert_raises(ArgumentError) { box.constrain(child, cross: auto) }
    end

    # Issue #73: findings, each a wrapped paragraph with its button beside it,
    # in a scrolled stack — no row counted by the app.
    it "stacks wrapped rows in a scroller, following a resize and an edit" do
      findings = Array.new(3) { paragraph("finding number #{_1} needs fixing") }
      stack = Component::Layout::Vertical.new
      findings.each do |finding|
        row = Component::Layout::Horizontal.new(spacing: 1)
        row.add(finding, Component::Layout::Expand[1], cross: auto)
        row.add(Component::Button.new("Fix"), Component::Layout::Fixed[7], cross: Component::Layout::Fixed[1])
        stack.add(row, auto)
      end
      scroller = Component::Scroller.new(stack).tap { _1.scrollbar_visibility = :gone }
      mount_at(scroller, Rect.new(0, 0, 40, 4))
      # 40 columns: each finding has 32 and fits on one row.
      assert_equal([1, 1, 1], findings.map { _1.rect.height })

      Testing.place(scroller, Rect.new(0, 0, 20, 4))
      scroller.flush_layout
      # 20 columns: 12 for each finding, which wraps to three rows.
      assert_equal([3, 3, 3], findings.map { _1.rect.height })
      assert_equal([0, 3, 6], stack.children.map { _1.rect.top })
      assert_equal 9, stack.rect.height

      findings.first.text = "short"
      Testing.loop
      assert_equal([1, 3, 3], findings.map { _1.rect.height })
      assert_equal 7, stack.rect.height
    end
  end
end
