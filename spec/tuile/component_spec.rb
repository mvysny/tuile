# frozen_string_literal: true

module Tuile
  describe Component do
    before { Screen.fake }
    after { Screen.close }

    it "smokes" do
      Component.new
    end

    context "rect=" do
      it "raises on non-Rect argument" do
        assert_raises(TypeError) { Component.new.rect = "not a rect" }
      end

      it "is no-op when set to the same rect" do
        c = Component.new
        c.rect = Rect.new(0, 0, 10, 5)
        Screen.instance.invalidated_clear
        c.rect = Rect.new(0, 0, 10, 5)
        assert !Screen.instance.invalidated?(c)
      end

      it "invalidates when rect changes" do
        c = Component::Layout::Absolute.new
        Screen.instance.content = c
        Screen.instance.invalidated_clear
        c.rect = Rect.new(0, 0, 10, 5)
        assert Screen.instance.invalidated?(c)
      end

      it "does not invalidate when the component is detached" do
        c = Component.new
        c.rect = Rect.new(0, 0, 10, 5)
        assert !Screen.instance.invalidated?(c)
      end

      it "calls on_width_changed when width changes" do
        width_changed = false
        klass = Class.new(Component) { define_method(:on_width_changed) { width_changed = true } }
        c = klass.new
        c.rect = Rect.new(0, 0, 20, 5)
        assert width_changed
      end

      it "does not call on_width_changed when only height changes" do
        width_changed = false
        klass = Class.new(Component) { define_method(:on_width_changed) { width_changed = true } }
        c = klass.new
        c.rect = Rect.new(0, 0, 10, 5)
        width_changed = false
        c.rect = Rect.new(0, 0, 10, 10)
        assert !width_changed
      end
    end

    context "active" do
      it "is false by default" do
        assert !Component.new.active?
      end

      it "can be set active even on a non-focusable component" do
        c = Component.new
        c.active = true
        assert c.active?
      end

      it "setting false when already false is a no-op" do
        c = Component.new
        assert !Screen.instance.invalidated?(c)
        c.active = false
        assert !Screen.instance.invalidated?(c)
      end
    end

    context "root" do
      it "returns self when component has no parent" do
        c = Component.new
        assert_equal c, c.root
      end

      it "returns parent when parent has no parent" do
        parent = Component.new
        child = Component.new
        child.send(:parent=, parent)
        assert_equal parent, child.root
      end

      it "returns the top-most ancestor in a deeper hierarchy" do
        root = Component.new
        middle = Component.new
        leaf = Component.new
        middle.send(:parent=, root)
        leaf.send(:parent=, middle)
        assert_equal root, leaf.root
      end
    end

    it "focusable? is false by default" do
      assert !Component.new.focusable?
    end

    it "tab_stop? is false by default" do
      assert !Component.new.tab_stop?
    end

    it "handle_key returns false" do
      assert_equal false, Component.new.handle_key("a")
    end

    context "#focus" do
      it "sets screen.focused to self" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        c = Class.new(Component) { def focusable? = true }.new
        layout.add([c])
        c.focus
        assert_equal c, screen.focused
      end
    end

    context "clear_background" do
      it "skips when rect is empty" do
        c = Component.new
        c.send(:clear_background)
        assert_equal [], Screen.instance.prints
      end

      it "prints spaces for each row of the rect" do
        c = Component.new
        c.rect = Rect.new(2, 3, 5, 2)
        c.send(:clear_background)
        assert_equal ["     ", "     "], Screen.instance.buffer.region_text(c.rect)
      end
    end

    context "bg_color" do
      it "defaults to nil" do
        assert_nil Component.new.bg_color
      end

      it "coerces the assigned color" do
        c = Component.new
        c.bg_color = 59
        assert_equal Color.new(59), c.bg_color
      end

      it "effective_bg_color returns the component's own color when set" do
        c = Component.new
        c.bg_color = 52
        assert_equal Color.new(52), c.effective_bg_color
      end

      it "effective_bg_color is nil when nothing is set anywhere" do
        assert_nil Component.new.effective_bg_color
      end

      it "effective_bg_color inherits the nearest ancestor's color" do
        root = Component.new
        mid = Component.new
        leaf = Component.new
        mid.send(:parent=, root)
        leaf.send(:parent=, mid)
        root.bg_color = 52
        assert_equal Color.new(52), leaf.effective_bg_color
      end

      it "effective_bg_color prefers a nearer ancestor over a farther one" do
        root = Component.new
        leaf = Component.new
        leaf.send(:parent=, root)
        root.bg_color = 52
        leaf.bg_color = 22
        assert_equal Color.new(22), leaf.effective_bg_color
      end

      it "clear_background fills with the effective bg" do
        c = Component.new
        c.send(:rect=, Rect.new(0, 0, 2, 1))
        c.bg_color = 52
        c.send(:clear_background)
        assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "draw_line fills the effective bg behind spans that have none" do
        c = Component.new
        c.bg_color = 52
        c.send(:draw_line, 0, 0, StyledString.plain("hi"))
        assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "draw_line leaves an explicit span bg untouched" do
        c = Component.new
        c.bg_color = 52
        c.send(:draw_line, 0, 0, StyledString.styled("hi", bg: :red))
        assert_equal Color::RED, Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "draw_line does not fill when no bg is inherited" do
        c = Component.new
        c.send(:draw_line, 0, 0, StyledString.plain("hi"))
        assert_nil Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "draw_char fills the effective bg when the style has none" do
        c = Component.new
        c.bg_color = 52
        c.send(:draw_char, 0, 0, "x")
        assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "keeps a Theme::Ref unresolved in the reader" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        c = Component.new
        c.bg_color = Theme.ref(:panel_bg)
        assert_equal Theme.ref(:panel_bg), c.bg_color
      end

      it "effective_bg_color resolves a Theme::Ref against the current theme" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        c = Component.new
        c.bg_color = Theme.ref(:panel_bg)
        assert_equal Color.palette(52), c.effective_bg_color
      end

      it "effective_bg_color tracks a theme swap without reassigning the Ref" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        c = Component.new
        c.bg_color = Theme.ref(:panel_bg)
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(22) })
        assert_equal Color.palette(22), c.effective_bg_color
      end

      it "resolves an ancestor's Theme::Ref for a descendant" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        root = Component.new
        leaf = Component.new
        leaf.send(:parent=, root)
        root.bg_color = Theme.ref(:panel_bg)
        assert_equal Color.palette(52), leaf.effective_bg_color
      end

      it "accepts a Theme::Ref to a built-in chrome token and resolves it live" do
        Screen.instance.theme = Theme::DARK
        c = Component.new
        c.bg_color = Theme.ref(:input_bg_color) # no custom token needed, no raise
        assert_equal Theme::DARK.input_bg_color, c.effective_bg_color
        Screen.instance.theme = Theme::LIGHT
        assert_equal Theme::LIGHT.input_bg_color, c.effective_bg_color
      end

      it "raises eagerly at assignment for an unknown token" do
        assert_raises(KeyError) { Component.new.bg_color = Theme.ref(:nonesuch) }
      end
    end

    context "#repaint default" do
      def container_with(children_rects)
        kids = children_rects.map do |r|
          Component.new.tap { |c| c.send(:rect=, r) }
        end
        klass = Class.new(Component) do
          define_method(:children) { kids }
        end
        klass.new
      end

      it "is a no-op when rect is empty" do
        c = Component.new
        Screen.instance.prints.clear
        c.repaint
        assert_equal [], Screen.instance.prints
      end

      it "clears background on a leaf with non-empty rect" do
        c = Component.new
        c.send(:rect=, Rect.new(0, 0, 3, 1))
        c.repaint
        assert_equal ["   "], Screen.instance.buffer.region_text(c.rect)
      end

      it "does not clear when children fully tile the rect" do
        container = container_with([Rect.new(0, 0, 5, 2)])
        container.send(:rect=, Rect.new(0, 0, 5, 2))
        child = container.children.first
        Screen.instance.invalidated_clear
        container.repaint
        assert !Screen.instance.invalidated?(child)
      end

      it "treats overlapping siblings as tiling (sum >= area)" do
        # Two overlapping children together exceed the parent area; the
        # area-equality check should not false-positive a "gap" here.
        container = container_with([Rect.new(0, 0, 5, 2), Rect.new(0, 0, 5, 2)])
        container.send(:rect=, Rect.new(0, 0, 5, 2))
        Screen.instance.invalidated_clear
        container.repaint
        assert(container.children.none? { Screen.instance.invalidated?(_1) })
      end

      it "clears and invalidates children when children leave gaps" do
        container = container_with([Rect.new(0, 0, 2, 1)])
        container.send(:rect=, Rect.new(0, 0, 5, 2))
        gappy = container.children.first
        Screen.instance.invalidated_clear
        container.repaint
        assert_equal ["     ", "     "], Screen.instance.buffer.region_text(container.rect)
        assert Screen.instance.invalidated?(gappy)
      end

      it "ignores children with empty rects when computing coverage" do
        # The single tiling child fully covers the parent; the empty
        # sibling contributes zero. No gap, no clear.
        container = container_with([Rect.new(0, 0, 5, 2), Rect.new(0, 0, 0, 0)])
        container.send(:rect=, Rect.new(0, 0, 5, 2))
        Screen.instance.invalidated_clear
        container.repaint
        assert(container.children.none? { Screen.instance.invalidated?(_1) })
      end
    end

    it "cursor_position returns nil by default" do
      assert_nil Component.new.cursor_position
    end

    context "#attached?" do
      it "is true when root is the screen content" do
        layout = Component::Layout::Absolute.new
        child = Class.new(Component) { def focusable? = true }.new
        layout.add(child)
        Screen.instance.content = layout
        assert child.attached?
        assert layout.attached?
      end

      it "is true when root is a popup" do
        list = Component::List.new
        popup = Component::Popup.new(content: list)
        Screen.instance.add_popup(popup)
        assert popup.attached?
        assert list.attached?
      end

      it "is false for an orphan component" do
        assert !Component.new.attached?
      end

      it "is false once detached from the screen content" do
        layout = Component::Layout::Absolute.new
        child = Class.new(Component) { def focusable? = true }.new
        layout.add(child)
        Screen.instance.content = layout
        layout.remove(child)
        assert !child.attached?
      end
    end

    context "#on_child_removed" do
      def focusable
        Class.new(Component) { def focusable? = true }.new
      end

      it "refocuses to self when the focused component was the removed child" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        child = focusable
        layout.add(child)
        screen.focused = child

        layout.remove(child)
        assert_equal layout, screen.focused
      end

      it "refocuses to self when the focused component was a descendant of the removed subtree" do
        screen = Screen.instance
        outer = Component::Layout::Absolute.new
        screen.content = outer
        inner = Component::Layout::Absolute.new
        leaf = focusable
        inner.add(leaf)
        outer.add(inner)
        screen.focused = leaf

        outer.remove(inner)
        assert_equal outer, screen.focused
      end

      it "leaves focus alone when the focused component is unrelated to the removal" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        sibling = focusable
        removed = focusable
        layout.add([sibling, removed])
        screen.focused = sibling

        layout.remove(removed)
        assert_equal sibling, screen.focused
      end

      it "is a no-op in a detached subtree (does not raise nor mutate screen.focused)" do
        screen = Screen.instance
        attached_layout = Component::Layout::Absolute.new
        anchor = focusable
        attached_layout.add(anchor)
        screen.content = attached_layout
        screen.focused = anchor

        detached = Component::Layout::Absolute.new
        child = focusable
        detached.add(child)

        detached.remove(child)
        assert_equal anchor, screen.focused
      end
    end

    context "#on_theme_changed" do
      it "is a no-op by default" do
        Component.new.on_theme_changed
      end

      it "fires the assigned listener" do
        c = Component.new
        fired = 0
        c.on_theme_changed = -> { fired += 1 }
        c.on_theme_changed
        assert_equal 1, fired
      end

      it "an overriding subclass calling super keeps the listener firing" do
        subclass = Class.new(Component) do
          attr_reader :hook_calls

          def on_theme_changed
            @hook_calls = (@hook_calls || 0) + 1
            super
          end
        end
        c = subclass.new
        fired = 0
        c.on_theme_changed = -> { fired += 1 }
        c.on_theme_changed
        assert_equal 1, c.hook_calls
        assert_equal 1, fired
      end
    end

    it "invalidate adds component to screen invalidated set when attached" do
      c = Component::Layout::Absolute.new
      Screen.instance.content = c
      Screen.instance.invalidated_clear
      c.send(:invalidate)
      assert Screen.instance.invalidated?(c)
    end

    it "invalidate is a no-op when the component is detached" do
      c = Component.new
      c.send(:invalidate)
      assert !Screen.instance.invalidated?(c)
    end
  end
end
