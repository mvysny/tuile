# frozen_string_literal: true

module Tuile
  describe Component::Overlay do
    before { Screen.fake } # 160x50
    after { Screen.close }

    def list_of(lines)
      Component::List.new.tap { _1.lines = lines }
    end

    def at(rect = Rect.new(0, 0, 10, 1)) = Component::Overlay::At[rect]

    # A placement that records the anchor rect the pane resolved for it.
    def spy_placement
      @spy_placement ||= Data.define(:anchor, :seen) do
        include Component::Overlay::Placement

        def rect_for(_overlay, _screen_size, anchor_rect)
          seen << anchor_rect
          Rect.new(0, 0, 4, 1)
        end
      end
    end

    it "smokes" do
      o = Component::Overlay.new
      o.open(at)
      assert o.open?
      o.close
      assert !o.open?
    end

    it "close is a no-op when the overlay is not open" do
      o = Component::Overlay.new
      o.close # never opened
      assert !o.open?

      o.open(at)
      o.close
      o.close # already closed
      assert !o.open?
    end

    it "returns self from open, so construct-and-mount is one expression" do
      o = Component::Overlay.new.open(at)
      assert o.open?
    end

    context "parenting" do
      it "refuses a layout, which could neither place, hide nor dismiss it" do
        o = Component::Overlay.new(content: list_of(%w[a]))
        layout = Component::Layout::Absolute.new
        e = assert_raises(Tuile::Error) { layout.add(o) }
        assert_includes e.message, "belongs on the popup stack"
      end

      it "leaves the tree untouched when it refuses" do
        o = Component::Overlay.new
        layout = Component::Layout::Absolute.new
        assert_raises(Tuile::Error) { layout.add(o) }
        assert_empty layout.children
        assert_nil o.parent
      end

      it "refuses the pane's content slot too — `open` is the door" do
        assert_raises(Tuile::Error) { Screen.instance.content = Component::Overlay.new }
      end

      it "holds for every subclass" do
        layout = Component::Layout::Absolute.new
        assert_raises(Tuile::Error) { layout.add(Component::Popup.new) }
        assert_raises(Tuile::Error) { layout.add(Component::ListDropdown.new) }
      end

      it "accepts the popup stack, and lets go again" do
        o = Component::Overlay.new.open(at)
        assert_equal Screen.instance.pane, o.parent
        o.close
        assert_nil o.parent
      end
    end

    it "has no class-level open factory — it could only ever build a bare Overlay" do
      assert !Component::Overlay.respond_to?(:open)
      assert !Component::Popup.respond_to?(:open)
      assert !Component::ListDropdown.respond_to?(:open)
    end

    it "accepts content via the constructor" do
      list = list_of(%w[a b c])
      assert_equal list, Component::Overlay.new(content: list).content
    end

    it "lays out content to fill the entire overlay rect" do
      list = list_of(["hello"])
      o = Component::Overlay.new(content: list)
      o.open(at(Rect.new(3, 4, 20, 2))).flush_layout
      assert_equal o.local_rect, list.rect
      assert_equal o.rect, list.absolute_rect
    end

    it "draws nothing on repaint" do
      o = Component::Overlay.new(content: list_of(["hello"]))
      o.open(at)
      Screen.instance.prints.clear
      repaint(o)
      assert_equal [], Screen.instance.prints
    end

    it "content inside a closed overlay does not invalidate or paint" do
      list = Component::List.new
      o = Component::Overlay.new(content: list)
      o.open(at)
      o.close
      assert !list.attached?
      Screen.instance.invalidated_clear
      Screen.instance.prints.clear

      list.lines = %w[a b c]
      assert !Screen.instance.invalidated?(list)
      Screen.instance.repaint
      assert_equal [], Screen.instance.prints
    end

    context "the non-modal contract" do
      # All three are load-bearing rather than incidental: an overlay that took
      # focus would land it outside the key-dispatch scope, where ScreenPane
      # delivers to nobody and every keystroke goes dead until Tab recovers.
      # Inherited by every subclass that isn't a Popup, which is what stops each
      # one having to remember to opt out.
      it "is not modal" do
        assert !Component::Overlay.new.modal?
      end

      it "is not focusable" do
        assert !Component::Overlay.new.focusable?
      end

      it "is not a tab stop" do
        assert !Component::Overlay.new.tab_stop?
      end

      it "does not grab focus or center when opened" do
        content = Component::Layout::Absolute.new
        field = Component::TextField.new
        Testing.place(field, Rect.new(0, 0, 10, 1))
        content.add(field)
        Screen.instance.content = content
        Screen.instance.focused = field

        Component::Overlay.new(content: list_of(%w[a b])).open(at)
        assert_equal field, Screen.instance.focused # focus untouched
      end
    end

    context "placement" do
      it "takes the rect its placement asks for on the next settle" do
        o = Component::Overlay.new(content: list_of(%w[a b])).open(at(Rect.new(12, 7, 20, 2)))
        o.flush_layout
        assert_equal Rect.new(12, 7, 20, 2), o.rect
        assert_equal at(Rect.new(12, 7, 20, 2)), o.placement
      end

      it "keeps it through a resize, which re-runs the pane's pass" do
        o = Component::Overlay.new(content: list_of(%w[a b])).open(at(Rect.new(12, 7, 20, 2)))
        Screen.instance.resize_terminal(100, 30)
        o.flush_layout
        assert_equal Rect.new(12, 7, 20, 2), o.rect
      end

      it "moves on the next settle when the placement changes" do
        o = Component::Overlay.new(content: list_of(%w[a b])).open(at(Rect.new(12, 7, 20, 2)))
        o.flush_layout
        o.placement = at(Rect.new(0, 3, 20, 2))
        assert_equal(Rect.new(12, 7, 20, 2), Tuile.without_strict_layout { o.rect })
        o.flush_layout
        assert_equal Rect.new(0, 3, 20, 2), o.rect
      end

      it "takes an app's own placement — anything that includes Placement" do
        bottom_left = Data.define do
          include Component::Overlay::Placement

          def rect_for(_overlay, screen_size, _anchor_rect) = Rect.new(0, screen_size.height - 2, 20, 2)
        end
        o = Component::Overlay.new(content: list_of(%w[a b])).open(bottom_left[])
        o.flush_layout
        assert_equal Rect.new(0, 48, 20, 2), o.rect
      end

      # The layout is deferred, so a bare duck's NoMethodError would otherwise
      # surface a settle later, with only ScreenPane in the backtrace.
      it "refuses a bare duck at the call that named it, not mid-pass" do
        duck = Object.new
        def duck.rect_for(_overlay, _screen_size, _anchor_rect) = Rect.new(0, 0, 4, 1)

        e = assert_raises(TypeError) { Component::Overlay.new.open(duck) }
        assert_includes e.message, "Tuile::Component::Overlay::Placement"
      end

      it "refuses one handed to placement= too" do
        o = Component::Overlay.new(content: list_of(%w[a])).open(at)
        assert_raises(TypeError) { o.placement = Object.new }
      end

      it "is unanchored by default, so a placement need only answer rect_for" do
        assert_nil Class.new { include Component::Overlay::Placement }.new.anchor
      end

      it "hands rect_for a nil anchor rect when the placement declares no anchor" do
        seen = []
        Component::Overlay.new(content: list_of(%w[a])).open(spy_placement[nil, seen]).flush_layout
        assert_equal [nil], seen
      end

      it "passes a Rect anchor straight through" do
        seen = []
        anchor = Rect.new(4, 3, 10, 1)
        Component::Overlay.new(content: list_of(%w[a])).open(spy_placement[anchor, seen]).flush_layout
        assert_equal [anchor], seen
      end

      # The pane resolves it, so no placement walks the tree — extent not rect,
      # plus attached? and ancestor visibility. `list_dropdown_spec`'s
      # "#anchor_to a component" covers following and losing one.
      it "resolves a component anchor to its extent on screen" do
        button = mount_at(Component::Button.new("ok"), Rect.new(4, 3, 30, 5))
        seen = []
        Component::Overlay.new(content: list_of(%w[a])).open(spy_placement[button, seen]).flush_layout
        assert_equal [Rect.new(4, 3, 6, 1)], seen
      end

      it "refuses a new placement while closed — open takes it" do
        e = assert_raises(Tuile::Error) { Component::Overlay.new.placement = at }
        assert_includes e.message, "#open"
        assert_nil Component::Overlay.new.placement
      end

      it "has no default, since nothing about a bare overlay says where it goes" do
        e = assert_raises(ArgumentError) { Component::Overlay.new.open }
        assert_includes e.message, "Overlay::At"
      end

      it "declares no size, so a centered placement is refused" do
        assert_raises(Tuile::Error) { Component::Overlay.new.open(Component::Overlay::Centered[]).flush_layout }
      end
    end

    context "full-repaint escalation" do
      attr_reader :tiled

      before do
        @tiled = Component::Label.new
        Screen.instance.content = @tiled
      end

      it "fully repaints when an open overlay moves clear of its previous cells" do
        o = Component::Overlay.new(content: list_of(["hi"]))
        o.open(at(Rect.new(0, 0, 6, 1))).flush_layout
        Screen.instance.invalidated_clear

        o.placement = at(Rect.new(11, 0, 6, 1))
        o.flush_layout
        assert Screen.instance.invalidated?(tiled)
      end
    end

    context "close_on_outside_click" do
      it "defaults to true" do
        assert Component::Overlay.new.close_on_outside_click?
      end

      it "is settable via the constructor and the writer" do
        o = Component::Overlay.new(close_on_outside_click: false)
        assert !o.close_on_outside_click?

        o.close_on_outside_click = true
        assert o.close_on_outside_click?
      end
    end

    # `D_visibility`. An overlay is dismissed, not hidden: #close is the
    # lifecycle, and a hidden-but-open modal would go on scoping keys and
    # swallowing clicks while painting nothing.
    context "visible=" do
      it "raises, pointing at close" do
        e = assert_raises(Tuile::Error) { Component::Overlay.new.visible = false }
        assert_includes e.message, "close it instead"
      end

      it "raises on a Popup too, and on a shown assignment" do
        assert_raises(Tuile::Error) { Component::Popup.new.visible = false }
        assert_raises(Tuile::Error) { Component::Popup.new.visible = true }
      end

      it "leaves the overlay showing" do
        o = Component::Overlay.new
        assert_raises(Tuile::Error) { o.visible = false }
        assert_predicate o, :visible?
      end

      # An overlay's *content* is an ordinary component and hides normally —
      # that is the supported way to make part of a dialog come and go.
      it "does not stop its content being hidden" do
        label = Component::Label.new("in a popup")
        popup = Component::Popup.new(content: label)
        popup.open
        label.visible = false
        refute_predicate label, :visible?
      end
    end

    context "on_close" do
      it "fires when the overlay is closed" do
        closed = 0
        o = Component::Overlay.new
        o.on_close { closed += 1 }
        o.open(at)
        o.close
        assert_equal 1, closed
      end

      # The whole reason it hangs off handle_detached rather than #close: a driver
      # keeping its own record of open overlays must not be able to drift.
      it "fires when the overlay is removed straight off the screen" do
        closed = 0
        o = Component::Overlay.new
        o.on_close { closed += 1 }
        o.open(at)
        Screen.instance.remove_popup(o)
        assert_equal 1, closed
      end

      it "fires when the screen is torn down under it" do
        closed = 0
        o = Component::Overlay.new
        o.on_close { closed += 1 }
        o.open(at)
        Screen.close
        assert_equal 1, closed
        Screen.fake # the `after` hook closes again
      end

      it "does not fire when a closed overlay is closed again" do
        closed = 0
        o = Component::Overlay.new
        o.on_close { closed += 1 }
        o.open(at)
        o.close
        o.close
        assert_equal 1, closed
      end

      it "sees a closed overlay" do
        seen = nil
        o = Component::Overlay.new
        o.on_close { seen = o.open? }
        o.open(at)
        o.close
        assert_equal false, seen
      end
    end
  end

  describe Component::Overlay::Placement do
    # The module is the protocol and nothing else: an includer that forgets
    # rect_for fails at the pane's first pass, rather than being placed at
    # whatever a stray method_missing returned.
    it "raises until an includer implements rect_for" do
      placement = Class.new { include Component::Overlay::Placement }.new
      assert_raises(NotImplementedError) { placement.rect_for(nil, Size.new(80, 24), nil) }
    end
  end
end
