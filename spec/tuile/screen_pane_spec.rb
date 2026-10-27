# frozen_string_literal: true

module Tuile
  describe ScreenPane do
    before { Screen.fake }
    after { Screen.close }
    let(:pane) { Screen.instance.pane }

    def at(rect) = Component::Overlay::At[rect]

    it "is the root of the component tree" do
      assert_nil pane.parent
      assert_equal pane, pane.root
    end

    it "reports itself as attached to the screen" do
      assert pane.attached?
    end

    it "owns no chrome of its own" do
      assert_empty pane.children
    end

    it "is exposed via Screen#pane" do
      assert_equal pane, Screen.instance.pane
    end

    context "children ordering" do
      # The order *is* the paint order (and the Tab order), and it is now
      # maintained by add_child's insert position rather than recomputed on
      # every read — so it needs a guard.
      it "is content, then overlays in stacking order" do
        content = Component::Layout::Absolute.new
        first = Component::Dialog.new
        second = Component::Dialog.new

        Screen.instance.content = content
        pane.add_overlay(first)
        pane.add_overlay(second)

        assert_equal [content, first, second], pane.children
      end

      it "keeps content first when it is swapped under open overlays" do
        overlay = Component::Dialog.new
        pane.add_overlay(overlay)
        replacement = Component::Layout::Absolute.new

        Screen.instance.content = Component::Layout::Absolute.new
        Screen.instance.content = replacement

        assert_equal [replacement, overlay], pane.children
      end

      it "closes an overlay out of order without disturbing the rest" do
        content = Component::Layout::Absolute.new
        first = Component::Dialog.new
        second = Component::Dialog.new
        Screen.instance.content = content
        pane.add_overlay(first)
        pane.add_overlay(second)

        pane.remove_overlay(first)

        assert_equal [content, second], pane.children
        assert_equal [second], pane.overlays, "the slot list and the child list must not drift"
      end
    end

    context "rect propagation" do
      it "gives content the whole pane rect when its rect is set" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        Screen.instance.resize_terminal(80, 24)
        layout.flush_layout
        assert_equal Rect.new(0, 0, 80, 24), layout.rect
      end

      it "relayouts on a height-only change" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        Screen.instance.resize_terminal(80, 24)
        Screen.instance.resize_terminal(80, 30)
        layout.flush_layout
        assert_equal Rect.new(0, 0, 80, 30), layout.rect
      end

      # D_empty_ancestor: a pass that skipped an empty pane stranded both at
      # their last rects, and an `At` overlay would keep its rect in a pane with
      # no cells.
      it "collapses content and overlays when the terminal shrinks to nothing, and restores them" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        overlay = Component::Overlay.new
        overlay.open(at(Rect.new(1, 1, 5, 2)))
        Screen.instance.resize_terminal(0, 0)
        layout.flush_layout
        assert_equal [Rect.new(0, 0, 0, 0)] * 2, [layout.rect, overlay.rect]
        Screen.instance.resize_terminal(40, 10)
        layout.flush_layout
        assert_equal [Rect.new(0, 0, 40, 10), Rect.new(1, 1, 5, 2)], [layout.rect, overlay.rect]
      end
    end

    context "parenting" do
      it "parents content when assigned" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        assert_equal pane, layout.parent
      end

      it "parents overlays when added" do
        list = Component::List.new
        list.lines = ["a"]
        overlay = Component::Dialog.new(content: list)
        Screen.instance.add_overlay(overlay)
        assert_equal pane, overlay.parent
      end

      it "detaches overlay parent when removed" do
        list = Component::List.new
        list.lines = ["a"]
        overlay = Component::Dialog.new(content: list)
        Screen.instance.add_overlay(overlay)
        Screen.instance.remove_overlay(overlay)
        assert_nil overlay.parent
      end

      it "repaints overlay content on reopen even when its rect is unchanged" do
        # Tiled content that covers the overlay's cells, so closing the overlay and
        # repainting the scene overpaints them — the reopen must repaint the
        # overlay's *content*, not just the (blank) wrapper. Regression: add_overlay
        # invalidated only the wrapper, so an unchanged-rect reopen stayed blank.
        Screen.instance.content = Component::Label.new.tap { _1.text = "\n" * 20 }
        list = Component::List.new.tap { _1.lines = %w[alpha] }
        overlay = Component::Overlay.new(content: list)
        region = -> { Screen.instance.buffer.region_text(overlay.absolute_rect).first.strip }

        Screen.instance.add_overlay(overlay, at(Rect.new(0, 5, 10, 1)))
        Screen.instance.repaint
        assert_equal "alpha", region.call

        Screen.instance.remove_overlay(overlay)
        Screen.instance.repaint # scene repaint overpaints the overlay's old cells
        Screen.instance.add_overlay(overlay, at(Rect.new(0, 5, 10, 1))) # same rect, same content
        Screen.instance.repaint
        assert_equal "alpha", region.call
      end
    end

    context "validation" do
      it "rejects non-Component content" do
        assert_raises(TypeError) { Screen.instance.content = "nope" }
      end

      it "rejects content that already has a parent" do
        layout = Component::Layout::Absolute.new
        Component::Dialog.new(content: layout)
        assert_raises(ArgumentError) { Screen.instance.content = layout }
      end

      it "rejects a non-Dialog as an overlay" do
        assert_raises(TypeError) { Screen.instance.add_overlay(Component::Label.new) }
      end

      it "rejects an overlay that already has a parent" do
        overlay = Component::Dialog.new(content: Component::Label.new)
        Screen.instance.add_overlay(overlay)
        assert_raises(ArgumentError) { Screen.instance.add_overlay(overlay) }
      end

      it "rejects removing an overlay that is not open" do
        overlay = Component::Dialog.new(content: Component::Label.new)
        # Screen#remove_overlay silently no-ops on a non-open overlay, so reach the
        # pane's guard directly.
        assert_raises(Tuile::Error) { pane.remove_overlay(overlay) }
      end
    end

    context "handle_key? (bubble dispatch)" do
      # Builds `content` = a Layout holding the given children and returns it.
      def content_with(*children)
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(children)
        layout
      end

      def field(width = 10)
        f = Component::TextField.new
        Testing.place(f, Rect.new(0, 0, width, 1))
        f
      end

      # The scope root is the documented home for a scope-wide one-key binding
      # (a layout's jump-to-pane keys, a form's default button): it sees the key
      # only after the focus chain declined it.
      it "bubbles a one-key binding to the scope root, which may move focus" do
        target = Component::Button.new("two")
        layout = content_with(Component::Button.new("one"), target)
        layout.define_singleton_method(:handle_key?) do |key|
          next false unless key == "g"

          screen.focused = target
          true
        end
        Screen.instance.focused = layout.children.first

        assert pane.handle_key?("g")
        assert_equal target, Screen.instance.focused
      end

      it "does not reach the scope root when a focused field consumes the key" do
        f = field
        layout = content_with(f)
        layout.define_singleton_method(:handle_key?) { |_key| flunk "should not bubble" }
        Screen.instance.focused = f

        assert pane.handle_key?("g")
        assert_equal "g", f.text # typed into the field
        assert_equal f, Screen.instance.focused
      end

      it "delivers a freely-typed key to the focused component" do
        f = field
        content_with(f)
        Screen.instance.focused = f

        assert pane.handle_key?("z")
        assert_equal "z", f.text
      end

      it "delivers nothing when focus is nil" do
        f = field
        content_with(f)
        Screen.instance.focused = nil

        assert !pane.handle_key?("z")
        assert_equal "", f.text
      end

      it "bubbles an undeclined key up to an ancestor (overlay closes on q)" do
        list = Component::List.new
        list.lines = ["a"]
        list.cursor = Component::List::Cursor.new
        overlay = Component::Dialog.new(content: list)
        overlay.open
        assert_equal list, Screen.instance.focused # open cascades focus onto the list

        assert pane.handle_key?("q") # list declines q; overlay handles it
        assert !overlay.open?
      end

      it "does not deliver to content beneath an open overlay (modal)" do
        beneath = field
        content_with(beneath)
        Screen.instance.focused = beneath

        overlay_got = []
        inner = Class.new(Component) { def focusable? = true }.new
        Testing.place(inner, Rect.new(0, 0, 5, 1))
        inner.define_singleton_method(:handle_key?) { |k| overlay_got << k }
        Component::Dialog.new(content: inner).open # cascades focus onto `inner`

        pane.handle_key?("z")
        assert_equal ["z"], overlay_got # the open overlay's content receives it
        assert_equal "", beneath.text # content beneath is untouched
      end
    end

    context "handle_paste (focused component only, no bubble)" do
      def content_with(*children)
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(children)
        layout
      end

      def field(width = 10)
        f = Component::TextField.new
        Testing.place(f, Rect.new(0, 0, width, 1))
        f
      end

      it "delivers the whole text to the focused component" do
        f = field
        content_with(f)
        Screen.instance.focused = f

        assert pane.handle_paste("hello")
        assert_equal "hello", f.text
      end

      it "delivers nothing when focus is nil" do
        f = field
        content_with(f)
        Screen.instance.focused = nil

        assert !pane.handle_paste("hello")
        assert_equal "", f.text
      end

      it "does not bubble to an ancestor when the focused component declines" do
        seen = []
        inert = Class.new(Component) { def focusable? = true }.new
        layout = content_with(inert)
        layout.define_singleton_method(:handle_paste) do |text|
          seen << text
          true
        end
        Screen.instance.focused = inert

        assert !pane.handle_paste("up here")
        assert_equal [], seen # the ancestor is never offered it
      end

      it "does not deliver to content beneath an open modal overlay" do
        beneath = field
        content_with(beneath)
        Screen.instance.focused = beneath

        inner = field
        Component::Dialog.new(content: inner).open # cascades focus onto `inner`

        assert pane.handle_paste("scoped")
        assert_equal "scoped", inner.text
        assert_equal "", beneath.text
      end

      it "reports unhandled when nothing on the chain takes it" do
        inert = Class.new(Component) { def focusable? = true }.new
        content_with(inert)
        Screen.instance.focused = inert

        assert !pane.handle_paste("nobody wants this")
      end
    end

    context "non-modal overlays" do
      def field(width = 10)
        f = Component::TextField.new
        Testing.place(f, Rect.new(0, 0, width, 1))
        f
      end

      def list_of(line)
        Component::List.new.tap { _1.lines = [line] }
      end

      it "modal_overlay ignores non-modal overlays but finds a modal overlay" do
        Screen.instance.add_overlay(Component::Overlay.new(content: Component::Label.new), at(Rect.new(0, 0, 5, 1)))
        assert_nil pane.modal_overlay

        modal = Component::Dialog.new(content: Component::Label.new)
        Screen.instance.add_overlay(modal)
        assert_equal modal, pane.modal_overlay
      end

      it "delivers keys to the focused content while an overlay floats above it" do
        f = field
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(f)
        Screen.instance.focused = f
        Component::Overlay.new(content: Component::Label.new).open(at(Rect.new(0, 0, 5, 1)))

        assert pane.handle_key?("z")
        assert_equal "z", f.text # the editor keeps receiving keys
      end

      it "routes a click outside the overlay through to the content beneath" do
        clicks = []
        beneath = Class.new(Component) { def focusable? = true }.new
        Testing.place(beneath, Rect.new(0, 0, 80, 40))
        beneath.define_singleton_method(:handle_mouse_down?) { |e| clicks << e.point }
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(beneath)

        overlay = Component::Overlay.new(content: list_of("a"))
        overlay.open(at(Rect.new(50, 1, 5, 3)))

        Screen.instance.click(2, 2) # outside the overlay rect
        assert_equal [Point.new(2, 2)], clicks
      end

      it "routes a click inside the overlay to the overlay, not the content" do
        clicks = []
        beneath = Class.new(Component) { def focusable? = true }.new
        Testing.place(beneath, Rect.new(0, 0, 80, 40))
        beneath.define_singleton_method(:handle_mouse_down?) { |_| clicks << :beneath }
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(beneath)

        inner = list_of("a")
        inner.define_singleton_method(:handle_mouse_down?) { |_| clicks << :overlay }
        overlay = Component::Overlay.new(content: inner)
        overlay.open(at(Rect.new(50, 1, 5, 3)))

        Screen.instance.click(51, 2) # inside the overlay rect
        assert_equal [:overlay], clicks
      end
    end
    context "outside-click dismissal" do
      def list_of(line) = Component::List.new.tap { _1.lines = [line] }

      def click_at(x, y) = Screen.instance.click(x, y)

      def overlay_at(rect, **kwargs)
        Component::Overlay.new(content: list_of("a"), **kwargs).tap do |o|
          o.open(at(rect))
        end
      end

      it "closes an open overlay on a left click that misses it" do
        o = overlay_at(Rect.new(50, 1, 5, 3))
        Screen.instance.click(2, 2)
        assert !o.open?
      end

      it "leaves an overlay open when the click lands inside it" do
        o = overlay_at(Rect.new(50, 1, 5, 3))
        Screen.instance.click(51, 2)
        assert o.open?
      end

      it "leaves an overlay open when it opted out" do
        o = overlay_at(Rect.new(50, 1, 5, 3), close_on_outside_click: false)
        Screen.instance.click(2, 2)
        assert o.open?
      end

      it "dismisses a modal overlay too, and still swallows the click" do
        clicks = []
        beneath = Class.new(Component) { def focusable? = true }.new
        Testing.place(beneath, Rect.new(0, 0, 80, 40))
        beneath.define_singleton_method(:handle_mouse_down?) { |_| clicks << :beneath }
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(beneath)

        modal = Component::Dialog.new(content: list_of("a"))
        modal.open(at(Rect.new(50, 1, 5, 3)))

        Screen.instance.click(2, 2)
        assert !modal.open?
        assert_empty clicks # modality ate it: one click to dismiss, another to act
      end

      # A MenuBar cascade must vanish whole on one click, not peel one panel
      # per click — so this is every miss, not just the topmost.
      it "closes every overlay the click missed, not just the topmost" do
        a = overlay_at(Rect.new(50, 1, 5, 3))
        b = overlay_at(Rect.new(60, 1, 5, 3))
        Screen.instance.click(2, 2)
        assert !a.open?
        assert !b.open?
      end

      it "ignores scroll and right clicks" do
        o = overlay_at(Rect.new(50, 1, 5, 3))
        Screen.instance.scroll(:down, 2, 2)
        Screen.instance.click(2, 2, button: :right)
        assert o.open?
      end

      # The snapshot half of the ordering rule: an overlay the delivered click
      # *opened* is not in the set, so it does not immediately eat itself.
      it "does not dismiss an overlay that the delivered click opened" do
        opener = Class.new(Component) do
          attr_accessor :overlay

          def focusable? = true

          def handle_mouse_down?(_event)
            overlay.open(Component::Overlay::At[Rect.new(50, 1, 5, 3)])
            true
          end
        end.new
        Testing.place(opener, Rect.new(0, 0, 80, 40))
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(opener)
        opener.overlay = Component::Overlay.new(content: list_of("a"))

        Screen.instance.click(2, 2)
        assert opener.overlay.open?
      end

      # The other half: the delivered click closes it first, and the dismissal
      # then no-ops instead of reopening it.
      it "lets a widget toggle its own overlay shut from a click on its face" do
        toggler = Class.new(Component) do
          attr_accessor :overlay

          def focusable? = true

          def handle_mouse_down?(_event)
            overlay.open? ? overlay.close : overlay.open(Component::Overlay::At[Rect.new(50, 1, 5, 3)])
            true
          end
        end.new
        Testing.place(toggler, Rect.new(0, 0, 80, 40))
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        layout.add(toggler)
        toggler.overlay = Component::Overlay.new(content: list_of("a"))
        toggler.overlay.open(at(Rect.new(50, 1, 5, 3)))

        Screen.instance.click(2, 2) # on the face, missing the overlay
        assert !toggler.overlay.open?
      end

      # "Outside" spans the owner chain: the overlay the click hit is kept, and so
      # is every overlay that one belongs to. Ownership is declared, never
      # inferred from stacking order — between unrelated overlays that order is
      # merely the order they opened in.
      context "the owner chain" do
        # A host overlay with a component inside it, plus an overlay that
        # component opened — the ComboBox-in-a-dialog shape.
        def host_and_owned
          driver = Class.new(Component) { def focusable? = true }.new
          host = Component::Dialog.new(content: driver)
          host.open(at(Rect.new(10, 10, 20, 5)))

          owned = overlay_at(Rect.new(12, 15, 10, 3)) # hangs below the host
          owned.owner = driver
          [host, owned]
        end

        it "keeps a host when the click lands in an overlay its own child opened" do
          host, owned = host_and_owned
          click_at(13, 16) # inside the owned overlay, outside the host
          assert host.open?
          assert owned.open?
        end

        it "dismisses the owned overlay when the host itself is clicked" do
          host, owned = host_and_owned
          click_at(11, 11) # inside the host, outside the overlay
          assert host.open?
          assert !owned.open?
        end

        it "keeps the whole chain, not just one link" do
          host, owned = host_and_owned
          grandchild = overlay_at(Rect.new(24, 15, 6, 3))
          grandchild.owner = owned

          click_at(25, 16) # inside the grandchild only
          assert host.open?, "the chain must be walked transitively"
          assert owned.open?
        end

        it "leaves unrelated overlays independent — clicking one dismisses the other" do
          a = overlay_at(Rect.new(50, 1, 5, 3))
          b = overlay_at(Rect.new(60, 1, 5, 3))
          click_at(61, 2)
          assert !a.open?
          assert b.open?
        end

        # A mis-wired cycle must terminate rather than hang the UI thread.
        it "terminates on an owner cycle" do
          a = overlay_at(Rect.new(50, 1, 5, 3))
          b = overlay_at(Rect.new(60, 1, 5, 3))
          a.owner = b
          b.owner = a

          click_at(61, 2)
          assert a.open?, "both are in the cycle, so both are kept"
          assert b.open?
        end
      end

      it "survives a handler that closes further overlays mid-dismissal" do
        a = overlay_at(Rect.new(50, 1, 5, 3))
        b = overlay_at(Rect.new(60, 1, 5, 3))
        a.on_close { b.close }

        Screen.instance.click(2, 2)
        assert !a.open?
        assert !b.open?
      end
    end
  end
end
