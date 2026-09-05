# frozen_string_literal: true

module Tuile
  # {Component::Layout::Box} is abstract, so the shared machinery is exercised
  # through {Component::Layout::Vertical}; the axis mapping itself is specced in
  # vertical_spec / horizontal_spec.
  describe Component::Layout::Box do
    before { Screen.fake }
    after { Screen.close }

    # Constraint shorthands. Methods rather than constants: a constant assigned
    # inside a block lands in the enclosing `module Tuile`, where it would shadow
    # a Zeitwerk-managed name.
    def fixed(cells) = Component::Layout::Fixed[cells]
    def percent(share) = Component::Layout::Percent[share]
    def expand(weight) = Component::Layout::Expand[weight]
    def insets(**edges) = Component::Layout::Insets[**edges]

    # @return [Component::Layout::Vertical]
    def box(**) = Component::Layout::Vertical.new(**)

    # @return [Array<Integer>] each child's height, in child order.
    def heights(layout) = layout.children.map { |c| c.rect.height }

    # @return [Array<Integer>] each child's top edge, in child order.
    def tops(layout) = layout.children.map { |c| c.rect.top }

    # @return [Array<Integer>] each child's left edge, in child order.
    def lefts(layout) = layout.children.map { |c| c.rect.left }

    # @return [Boolean] true when no child paints anything.
    def all_empty?(layout) = layout.children.all? { |c| c.rect.empty? }

    context "abstract" do
      it "raises NotImplementedError when the axis hooks are missing" do
        bare = Component::Layout::Box.new
        bare.add(Component.new, fixed(1))
        assert_raises(NotImplementedError) { bare.rect = Rect.new(0, 0, 10, 10) }
      end
    end

    context "main axis" do
      it "gives a Fixed child exactly its cells" do
        layout = box
        layout.add(Component.new, fixed(3))
        layout.rect = Rect.new(0, 0, 10, 10)
        assert_equal [3], heights(layout)
      end

      it "packs children from the start edge, leaving slack at the end" do
        layout = box
        layout.add([Component.new, Component.new], fixed(2))
        layout.rect = Rect.new(0, 0, 10, 10)
        assert_equal [Rect.new(0, 0, 10, 2), Rect.new(0, 2, 10, 2)],
                     layout.children.map(&:rect)
      end

      it "separates children by spacing" do
        layout = box(spacing: 2)
        layout.add([Component.new, Component.new], fixed(1))
        layout.rect = Rect.new(0, 0, 10, 10)
        assert_equal [0, 3], tops(layout)
      end

      it "insets children by padding" do
        layout = box(padding: insets(top: 2, left: 3, right: 1))
        layout.add(Component.new, fixed(1))
        layout.rect = Rect.new(0, 0, 10, 10)
        assert_equal Rect.new(3, 2, 6, 1), layout.children.first.rect
      end

      it "gives an Expand child everything left over" do
        layout = box
        layout.add(Component.new, fixed(3))
        layout.add(Component.new, expand(1))
        layout.rect = Rect.new(0, 0, 10, 10)
        assert_equal [3, 7], heights(layout)
      end

      it "splits between Expand children in proportion to their weights" do
        layout = box
        layout.add(Component.new, expand(1))
        layout.add(Component.new, expand(3))
        layout.rect = Rect.new(0, 0, 10, 12)
        assert_equal [3, 9], heights(layout)
      end

      # The whole point of one-cell-at-a-time: "last Expand absorbs the
      # remainder" would give 2,2,2,2,4 here — a visible 2x discrepancy.
      it "hands the remainder to the earliest Expand children, one cell each" do
        layout = box
        5.times { layout.add(Component.new, expand(1)) }
        layout.rect = Rect.new(0, 0, 10, 12)
        assert_equal [3, 3, 2, 2, 2], heights(layout)
      end

      it "never loses a cell to rounding" do
        layout = box
        7.times { layout.add(Component.new, expand(1)) }
        layout.rect = Rect.new(0, 0, 10, 30)
        assert_equal 30, heights(layout).sum
      end
    end

    context "Percent" do
      it "takes its share of the available extent" do
        layout = box
        layout.add(Component.new, percent(25))
        layout.rect = Rect.new(0, 0, 10, 20)
        assert_equal [5], heights(layout)
      end

      # Measured after spacing and padding come off, so these fit exactly rather
      # than overflowing by the gap between them.
      it "is measured after spacing and padding are deducted" do
        layout = box(spacing: 1, padding: insets(top: 2))
        layout.add([Component.new, Component.new], percent(50))
        layout.rect = Rect.new(0, 0, 10, 13)
        assert_equal [5, 5], heights(layout)
        assert_equal [2, 8], tops(layout)
      end
    end

    context "over-subscription" do
      it "starves in declaration order, giving the loser an empty rect" do
        layout = box
        3.times { layout.add(Component.new, fixed(4)) }
        layout.rect = Rect.new(0, 0, 10, 6)
        assert_equal [4, 2, 0], heights(layout)
        assert layout.children.last.rect.empty?
      end

      it "gives every child an empty rect when padding exceeds the extent" do
        layout = box(padding: 5)
        layout.add([Component.new, Component.new], fixed(1))
        layout.rect = Rect.new(0, 0, 4, 4)
        assert all_empty?(layout)
      end

      it "gives every child an empty rect when spacing alone exhausts the extent" do
        layout = box(spacing: 10)
        layout.add([Component.new, Component.new], expand(1))
        layout.rect = Rect.new(0, 0, 10, 5)
        assert_equal [0, 0], heights(layout)
      end
    end

    context "an empty rect of its own" do
      it "empties every child rather than stranding it at its last rect" do
        layout = box
        child = Component.new
        layout.add(child, fixed(1))
        layout.rect = Rect.new(0, 0, 40, 5)
        refute child.rect.empty?

        layout.rect = Rect.new(0, 0, 0, 5)
        assert child.rect.empty?, child.rect.inspect
      end

      it "propagates all the way down a nest of boxes" do
        layout = box
        inner = box
        leaf = Component.new
        inner.add(leaf, fixed(1))
        layout.add(inner, expand(1))
        layout.rect = Rect.new(0, 0, 40, 5)
        refute leaf.rect.empty?

        layout.rect = Rect.new(0, 0, 40, 0)
        assert leaf.rect.empty?, leaf.rect.inspect
      end

      it "stays silent during construction, when no rect has been assigned yet" do
        layout = box
        child = Component.new
        layout.add(child, fixed(1))
        assert child.rect.empty?
        refute Screen.instance.invalidated?(layout)
      end

      it "keeps a collapsed pane off the screen across a popup close" do
        # The reported bug (`D_empty_ancestor`): the pane's own labels kept their
        # rects, and Screen#remove_popup's needs_full_repaint painted them back.
        screen = Screen.instance
        root = Component::Layout::Horizontal.new
        sidebar = box
        sidebar.add(Component::Label.new.tap { _1.text = "SIDEBAR" }, fixed(1))
        root.add(Component::Label.new.tap { _1.text = "MAIN" }, Component::Layout::Expand[1])
        root.add(sidebar, Component::Layout::Fixed[20])
        screen.content = root
        screen.repaint
        assert_includes screen.buffer.row_text(0), "SIDEBAR"

        root.constrain(sidebar, Component::Layout::Fixed[0])
        screen.repaint
        refute_includes screen.buffer.row_text(0), "SIDEBAR"

        popup = Component::Popup.new
        screen.add_popup(popup)
        screen.repaint
        popup.close
        screen.repaint
        refute_includes screen.buffer.row_text(0), "SIDEBAR"
      end
    end

    # `D_visibility`. A hidden child is not a member of the sequence at all —
    # contrast a Fixed[0] child, which is, and keeps costing its gap.
    context "a hidden child" do
      it "gives its slot back to its siblings" do
        layout = box
        top = Component.new
        middle = Component.new
        bottom = Component.new
        layout.add([top, middle, bottom], expand(1))
        layout.rect = Rect.new(0, 0, 10, 9)
        assert_equal [3, 3, 3], heights(layout)

        middle.visible = false
        assert_equal [5, 0, 4], heights(layout)
      end

      it "costs no spacing, so hiding a middle child leaves no double gap" do
        layout = box(spacing: 1)
        top = Component.new
        middle = Component.new
        bottom = Component.new
        layout.add([top, middle, bottom], fixed(1))
        layout.rect = Rect.new(0, 0, 10, 9)
        assert_equal [0, 2, 4], tops(layout)

        middle.visible = false
        # Two shown children, one gap between them — not the three-gap
        # arithmetic a collapsed-but-present child would keep.
        assert_equal [0, 2], [top.rect.top, bottom.rect.top]
        assert_equal 1, bottom.rect.top - (top.rect.top + top.rect.height)
      end

      it "gets an empty rect at the box's origin" do
        layout = box
        child = Component.new
        layout.add(child, fixed(3))
        layout.rect = Rect.new(4, 2, 10, 9)

        child.visible = false
        assert_predicate child.rect, :empty?
        assert_equal 4, child.rect.left
        assert_equal 2, child.rect.top
      end

      it "keeps its constraints, so showing it restores the layout exactly" do
        layout = box(spacing: 1)
        top = Component.new
        middle = Component.new
        bottom = Component.new
        layout.add(top, fixed(2))
        layout.add(middle, fixed(3), cross: fixed(6), align: :center)
        layout.add(bottom, expand(1))
        layout.rect = Rect.new(0, 0, 10, 12)
        before = layout.children.map(&:rect)

        middle.visible = false
        middle.visible = true
        assert_equal before, layout.children.map(&:rect)
      end

      it "is skipped by Percent, which divides between the shown ones" do
        layout = box
        first = Component.new
        second = Component.new
        layout.add([first, second], percent(50))
        layout.rect = Rect.new(0, 0, 10, 10)
        assert_equal [5, 5], heights(layout)

        second.visible = false
        assert_equal 5, first.rect.height, "Percent is a share of the box, not of the shown children"
      end

      # #constrain writes the placement map, which a hidden child keeps — so the
      # new constraint is waiting for it when it comes back.
      it "takes a constraint assigned while hidden" do
        layout = box
        top = Component.new
        bottom = Component.new
        layout.add([top, bottom], fixed(2))
        layout.rect = Rect.new(0, 0, 10, 10)

        bottom.visible = false
        layout.constrain(bottom, fixed(5))
        bottom.visible = true
        assert_equal 5, bottom.rect.height
      end
    end

    context "cross axis" do
      it "fills the cross extent by default" do
        layout = box
        layout.add(Component.new, fixed(1))
        layout.rect = Rect.new(0, 0, 40, 10)
        assert_equal 40, layout.children.first.rect.width
      end

      it "honors a Fixed cross constraint" do
        layout = box
        layout.add(Component.new, fixed(1), cross: fixed(30))
        layout.rect = Rect.new(0, 0, 100, 10)
        assert_equal 30, layout.children.first.rect.width
      end

      it "clamps a Fixed cross constraint to what is available" do
        layout = box
        layout.add(Component.new, fixed(1), cross: fixed(30))
        layout.rect = Rect.new(0, 0, 12, 10)
        assert_equal 12, layout.children.first.rect.width
      end

      it "honors a Percent cross constraint" do
        layout = box
        layout.add(Component.new, fixed(1), cross: percent(50))
        layout.rect = Rect.new(0, 0, 40, 10)
        assert_equal 20, layout.children.first.rect.width
      end

      it "aligns a narrow child at :start, :center and :end" do
        layout = box
        %i[start center end].each do |align|
          layout.add(Component.new, fixed(1), cross: fixed(20), align:)
        end
        layout.rect = Rect.new(0, 0, 100, 10)
        assert_equal [0, 40, 80], lefts(layout)
      end

      it "offsets alignment from the padded inner rect, not the raw one" do
        layout = box(padding: insets(left: 4, right: 6))
        layout.add(Component.new, fixed(1), cross: fixed(10), align: :end)
        layout.rect = Rect.new(0, 0, 30, 10)
        # inner spans columns 4..23 (20 wide), so an :end-aligned 10 starts at 14.
        assert_equal 14, layout.children.first.rect.left
      end
    end

    context "#add" do
      it "applies one constraint to every element of an Enumerable" do
        layout = box
        layout.add([Component.new, Component.new, Component.new], fixed(2))
        layout.rect = Rect.new(0, 0, 10, 20)
        assert_equal [2, 2, 2], heights(layout)
      end

      it "raises when adding a non-component" do
        assert_raises(TypeError) { box.add("not a component") }
      end

      it "rejects an Expand passed as cross" do
        assert_raises(ArgumentError) { box.add(Component.new, fixed(1), cross: expand(1)) }
      end

      it "rejects an unknown main constraint" do
        assert_raises(ArgumentError) { box.add(Component.new, 3) }
      end

      it "rejects an unknown alignment" do
        assert_raises(ArgumentError) { box.add(Component.new, fixed(1), align: :middle) }
      end

      it "does not add the child when a constraint is rejected" do
        layout = box
        assert_raises(ArgumentError) { layout.add(Component.new, fixed(1), align: :middle) }
        assert_equal [], layout.children
      end

      it "defaults a child wired in through add_child to Fixed[1] filling the cross axis" do
        layout = box
        child = Component.new
        layout.send(:add_child, child)
        layout.rect = Rect.new(0, 0, 40, 10)
        assert_equal Rect.new(0, 0, 40, 1), child.rect
      end

      it "inserts at a given index, so a removed child goes back where it was" do
        layout = box
        top = Component.new
        bottom = Component.new
        layout.add([top, bottom], fixed(1))
        layout.rect = Rect.new(0, 0, 40, 10)

        layout.remove(top)
        assert_equal 0, bottom.rect.top

        layout.add(top, fixed(1), at: 0)
        assert_equal [top, bottom], layout.children
        assert_equal [0, 1], tops(layout)
      end

      it "inserts an Enumerable in order from the given index" do
        layout = box
        first = Component.new
        last = Component.new
        layout.add([first, last], fixed(1))
        middle = [Component.new, Component.new]
        layout.add(middle, fixed(1), at: 1)
        assert_equal [first, *middle, last], layout.children
      end
    end

    context "#constrain" do
      it "changes one axis and leaves the others standing" do
        layout = box
        child = Component.new
        layout.add(child, fixed(1), cross: fixed(10), align: :center)
        layout.rect = Rect.new(0, 0, 40, 10)
        assert_equal Rect.new(15, 0, 10, 1), child.rect

        layout.constrain(child, fixed(4))
        assert_equal Rect.new(15, 0, 10, 4), child.rect
      end

      it "swaps a child between constraint kinds without reinserting it" do
        layout = box
        header = Component.new
        body = Component.new
        layout.add(header, fixed(1))
        layout.add(body, fixed(5))
        layout.rect = Rect.new(0, 0, 40, 20)
        assert_equal [1, 5], heights(layout)

        layout.constrain(body, expand(1))
        assert_equal [1, 19], heights(layout)

        layout.constrain(body, percent(25))
        assert_equal [1, 5], heights(layout)
        assert_equal [header, body], layout.children
      end

      it "does not detach the child it re-constrains" do
        layout = box
        child = Component.new
        detached = false
        child.define_singleton_method(:on_detached) { detached = true }
        layout.add(child, fixed(1))
        Screen.instance.content = layout
        layout.constrain(child, expand(1))
        refute detached
        assert_equal layout, child.parent
      end

      it "collapses a child to an empty rect with Fixed[0], and its subtree with it" do
        layout = box
        inner = box
        leaf = Component.new
        inner.add(leaf, fixed(1))
        layout.add([inner, Component.new], expand(1))
        layout.rect = Rect.new(0, 0, 40, 10)
        refute leaf.rect.empty?

        layout.constrain(inner, fixed(0))
        assert inner.rect.empty?
        assert leaf.rect.empty?, leaf.rect.inspect
      end

      it "gives the collapsed child's space to its expanding siblings" do
        layout = box
        sidebar = Component.new
        main = Component.new
        layout.add(sidebar, expand(1))
        layout.add(main, expand(1))
        layout.rect = Rect.new(0, 0, 40, 10)
        assert_equal [5, 5], heights(layout)

        layout.constrain(sidebar, fixed(0))
        assert_equal [0, 10], heights(layout)
      end

      it "raises for a component that is not a child" do
        assert_raises(ArgumentError) { box.constrain(Component.new, fixed(1)) }
      end

      it "rejects an Expand passed as cross" do
        layout = box
        child = Component.new
        layout.add(child, fixed(1))
        assert_raises(ArgumentError) { layout.constrain(child, cross: expand(1)) }
      end

      it "rejects an unknown alignment, leaving the placement untouched" do
        layout = box
        child = Component.new
        layout.add(child, fixed(1), cross: fixed(10))
        layout.rect = Rect.new(0, 0, 40, 10)
        assert_raises(ArgumentError) { layout.constrain(child, align: :middle) }
        assert_equal Rect.new(0, 0, 10, 1), child.rect
      end

      it "does not relayout when nothing changed" do
        layout = box
        child = Component.new
        layout.add(child, fixed(1))
        layout.rect = Rect.new(0, 0, 40, 10)
        Screen.instance.invalidated_clear
        layout.constrain(child, fixed(1))
        refute Screen.instance.invalidated?(layout)
      end
    end

    context "relayout triggers" do
      it "assigns rects on add, after the layout already has one" do
        layout = box
        layout.rect = Rect.new(0, 0, 10, 10)
        child = Component.new
        layout.add(child, fixed(4))
        assert_equal Rect.new(0, 0, 10, 4), child.rect
      end

      it "does not raise when children are added before a rect is assigned" do
        layout = box
        layout.add(Component.new, fixed(1))
        assert layout.children.first.rect.empty?
      end

      # In a box the children move: Absolute can leave siblings alone, this can't.
      it "shifts the remaining children up on remove" do
        layout = box
        first = Component.new
        second = Component.new
        layout.add([first, second], fixed(2))
        layout.rect = Rect.new(0, 0, 10, 10)
        assert_equal 2, second.rect.top
        layout.remove(first)
        assert_equal 0, second.rect.top
      end

      it "invalidates the layout on remove even when children remain" do
        layout = box
        first = Component.new
        layout.add([first, Component.new], fixed(2))
        Screen.instance.content = layout
        Screen.instance.invalidated_clear
        layout.remove(first)
        assert Screen.instance.invalidated?(layout)
      end

      it "invalidates the layout on add" do
        layout = box
        Screen.instance.content = layout
        Screen.instance.invalidated_clear
        layout.add(Component.new, fixed(1))
        assert Screen.instance.invalidated?(layout)
      end

      it "drops the removed child's constraints" do
        layout = box
        child = Component.new
        layout.add(child, fixed(5))
        layout.remove(child)
        layout.add(child)
        layout.rect = Rect.new(0, 0, 10, 10)
        assert_equal [1], heights(layout)
      end
    end

    # No mutator calls screen.check_locked itself: Screen#invalidate does, and
    # Component#invalidate reaches it whenever attached. Pinned because the
    # obvious "fix" is to sprinkle explicit guards that are already redundant.
    context "thread confinement, inherited through invalidate" do
      # Runs `block` on a spawned thread. Anything other than a {Tuile::Error}
      # propagates out of `Thread#value`, so a real failure still surfaces.
      # @return [Tuile::Error, nil] the refusal, or nil if the block was allowed.
      def error_from(&block)
        Thread.new do
          block.call
          nil
        rescue Tuile::Error => e
          e
        end.value
      end

      let(:attached) do
        layout = box
        layout.add(Component.new, fixed(1))
        Screen.instance.content = layout
        layout.rect = Rect.new(0, 0, 10, 10)
        layout
      end

      it "refuses spacing= from another thread" do
        error = error_from { attached.spacing = 3 }
        assert_kind_of Tuile::Error, error
      end

      it "refuses padding= from another thread" do
        error = error_from { attached.padding = 2 }
        assert_kind_of Tuile::Error, error
      end

      it "refuses add from another thread" do
        error = error_from { attached.add(Component.new, fixed(1)) }
        assert_kind_of Tuile::Error, error
      end

      it "still allows a detached box to be assembled off-thread" do
        detached = box
        error = error_from do
          detached.add(Component.new, fixed(1))
          detached.rect = Rect.new(0, 0, 10, 10)
          detached.spacing = 2
        end
        assert_nil error
      end
    end

    context "#spacing=" do
      it "relayouts" do
        layout = box
        layout.add([Component.new, Component.new], fixed(1))
        layout.rect = Rect.new(0, 0, 10, 10)
        layout.spacing = 3
        assert_equal [0, 4], tops(layout)
      end

      it "rejects a negative value" do
        assert_raises(ArgumentError) { box.spacing = -1 }
      end

      it "rejects a non-Integer" do
        assert_raises(ArgumentError) { box.spacing = 1.5 }
      end
    end

    context "#padding=" do
      it "relayouts" do
        layout = box
        layout.add(Component.new, fixed(1))
        layout.rect = Rect.new(0, 0, 10, 10)
        layout.padding = insets(top: 3)
        assert_equal 3, layout.children.first.rect.top
      end

      it "coerces an Integer to a uniform inset" do
        layout = box(padding: 2)
        assert_equal insets(top: 2, right: 2, bottom: 2, left: 2), layout.padding
      end

      it "rejects a non-Insets, non-Integer" do
        assert_raises(ArgumentError) { box.padding = "1" }
      end
    end
  end
end
