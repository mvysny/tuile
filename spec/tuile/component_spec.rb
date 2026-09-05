# frozen_string_literal: true

module Tuile
  describe Component do
    before { Screen.fake }
    after { Screen.close }

    it "smokes" do
      Component.new
    end

    context "geometry readers" do
      it "size, width and height report the assigned rect" do
        c = Component.new
        c.rect = Rect.new(3, 4, 20, 6)
        assert_equal Size.new(20, 6), c.size
        assert_equal 20, c.width
        assert_equal 6, c.height
      end

      it "follow a reassigned rect, holding no state of their own" do
        c = Component.new
        c.rect = Rect.new(0, 0, 5, 5)
        c.rect = Rect.new(0, 0, 9, 2)
        assert_equal Size.new(9, 2), c.size
        assert_equal 9, c.width
        assert_equal 2, c.height
      end

      # Layout is top-down: a component reports the geometry it was given and
      # has no way to ask for a different one. A writer here would be the
      # deleted bottom-up content_size channel returning under a new name.
      it "are readers only — there is no size=, width= or height=" do
        c = Component.new
        refute_respond_to c, :size=
        refute_respond_to c, :width=
        refute_respond_to c, :height=
      end

      # Popup declares a Size | Fraction it asks the screen for; that is a
      # different concept from the Size it currently occupies, which is why the
      # two carry different names.
      it "coexist with Popup#declared_size, which is not rect.size" do
        p = Component::Popup.new(declared_size: Fraction::HALF)
        p.open
        assert_equal Fraction::HALF, p.declared_size
        assert_equal Size.new(80, 25), p.size # HALF of the 160x50 fake screen
      end
    end

    context "#id" do
      it "is nil until set" do
        assert_nil Component.new.id
      end

      it "round-trips a Symbol, and takes nil back" do
        c = Component.new
        c.id = :save
        assert_equal :save, c.id
        c.id = nil
        assert_nil c.id
      end

      # A String would never match a `get(id: :save)`, silently — so the
      # setter refuses it rather than coercing.
      it "refuses a String" do
        e = assert_raises(TypeError) { Component.new.id = "save" }
        assert_includes e.message, "expected Symbol or nil"
      end

      it "does not invalidate: nothing paints an id" do
        c = Component.new
        Screen.instance.content = c
        Screen.instance.invalidated_clear
        c.id = :save
        assert !Screen.instance.invalidated?(c)
      end

      # No uniqueness check anywhere in production: a detached tree cannot know
      # the screen, and two TabSheet panes may reuse an id since only one is
      # attached. Testing.get raising on two matches is the whole enforcement.
      it "does not enforce uniqueness" do
        layout = Component::Layout::Absolute.new
        2.times { layout.add(Component.new.tap { _1.id = :dupe }) }
        Screen.instance.content = layout
        assert_equal %i[dupe dupe], layout.children.map(&:id)
      end
    end

    context "#inspect" do
      # Object#inspect would walk parent, children and the Screen — dumping the
      # whole UI for one component.
      it "names the class and the rect, and omits an unset id" do
        c = Component.new
        c.rect = Rect.new(3, 4, 20, 6)
        assert_equal "#<Tuile::Component rect=(3,4 20x6)>", c.inspect
      end

      it "carries the id when set" do
        c = Component.new
        c.id = :save
        assert_equal "#<Tuile::Component id=:save rect=(0,0 0x0)>", c.inspect
      end

      it "does not recurse into the tree" do
        parent = Component::Layout::Absolute.new
        parent.add(Component.new)
        Screen.instance.content = parent
        refute_includes parent.inspect, "children"
      end

      # The hook, not an override, so two mixins each contribute through super
      # — a Checkbox includes HasValue and HasCaption, and shows both. They
      # appear in reverse include order, the last-included calling super first.
      it "appends what each mixin's inspect_details adds" do
        c = Component::Checkbox.new("Ready", value: true)
        assert_equal "#<Tuile::Component::Checkbox rect=(0,0 0x0) value=true caption=\"Ready\">", c.inspect
      end

      it "omits an empty caption and a nil value" do
        assert_equal "#<Tuile::Component::TextField rect=(0,0 0x0) value=\"\">", Component::TextField.new.inspect
        assert_equal "#<Tuile::Component::Window rect=(0,0 0x0)>", Component::Window.new.inspect
      end

      # A debug method must not build a megabyte to show 40 characters of it.
      it "truncates a long String value" do
        area = Component::TextArea.new
        area.text = "x" * 5_000
        assert_equal "#<Tuile::Component::TextArea rect=(0,0 0x0) value=\"#{"x" * 40}…\">", area.inspect
      end

      it "falls back to the anonymous form when the class has no name" do
        assert_includes Class.new(Component).new.inspect, "#<#<Class:"
      end

      it "keeps inspect_details protected, so it is not API" do
        assert !Component.new.respond_to?(:inspect_details)
      end
    end

    context "#extent" do
      # nil means "undeclared", which is not the same as rect.size: it is what
      # tells the default repaint to blank everything before the component
      # paints, as a Label with short text needs.
      it "is nil by default, and extent_rect falls back to the whole rect" do
        c = Component.new
        c.rect = Rect.new(2, 3, 10, 4)
        assert_nil c.extent
        assert_equal c.rect, c.extent_rect
      end

      it "an undeclared extent still blanks the whole rect" do
        c = Component.new
        Screen.instance.content = c
        c.rect = Rect.new(0, 0, 4, 1)
        Screen.instance.buffer.set_text(0, 0, StyledString.plain("XXXX"))
        c.repaint
        assert_equal "    ", Screen.instance.buffer.region_text(c.rect).first
      end

      # A declared extent equal to the rect is NOT the same as no declaration:
      # it promises the component paints those cells itself, so they must not be
      # blanked first (D_progress_bar).
      it "a declared extent equal to the rect blanks nothing" do
        c = Class.new(Component) { def extent = Size.new(4, 1) }.new
        Screen.instance.content = c
        c.rect = Rect.new(0, 0, 4, 1)
        Screen.instance.buffer.set_text(0, 0, StyledString.plain("XXXX"))
        c.repaint
        assert_equal "XXXX", Screen.instance.buffer.region_text(c.rect).first
      end

      # A Size, not a Rect: the extent always sits at the rect's top-left, so an
      # offset one is unrepresentable rather than merely undocumented.
      it "is a Size, and extent_rect places it" do
        c = Class.new(Component) { def extent = Size.new(4, 1) }.new
        c.rect = Rect.new(7, 5, 20, 3)
        assert_equal Size.new(4, 1), c.extent
        assert_equal Rect.new(7, 5, 4, 1), c.extent_rect
      end

      it "clear_outside_extent blanks the L a narrowed extent leaves" do
        c = Class.new(Component) { def extent = Size.new(4, 1) }.new
        Screen.instance.content = c
        c.rect = Rect.new(0, 0, 8, 3)
        Screen.instance.buffer.set_text(0, 0, StyledString.plain("XXXXXXXX"))
        Screen.instance.buffer.set_text(0, 1, StyledString.plain("XXXXXXXX"))

        c.send(:clear_outside_extent)
        # Row 0 keeps the extent's four columns and loses the tail; row 1 is
        # below the extent, so all of it goes.
        assert_equal "XXXX    ", Screen.instance.buffer.region_text(c.rect)[0]
        assert_equal "        ", Screen.instance.buffer.region_text(c.rect)[1]
      end

      it "leaves the extent's own cells alone, so an unchanged repaint re-emits nothing of it" do
        cb = Component::Checkbox.new.tap { _1.caption = "Enable" }
        Screen.instance.content = cb
        cb.rect = Rect.new(0, 0, 40, 1)
        Screen.instance.repaint
        Screen.instance.prints.clear

        Screen.instance.invalidate(cb)
        Screen.instance.repaint
        # Blanking cells it is about to repaint would mark them dirty and flush
        # would re-emit the whole caption (D_progress_bar).
        refute_includes Screen.instance.prints.join, "Enable"
      end
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

    it "handle_paste returns false" do
      assert_equal false, Component.new.handle_paste("pasted")
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
        assert_equal Color.new(52), c.send(:effective_bg_color)
      end

      it "effective_bg_color is nil when nothing is set anywhere" do
        assert_nil Component.new.send(:effective_bg_color)
      end

      it "effective_bg_color inherits the nearest ancestor's color" do
        root = Component.new
        mid = Component.new
        leaf = Component.new
        mid.send(:parent=, root)
        leaf.send(:parent=, mid)
        root.bg_color = 52
        assert_equal Color.new(52), leaf.send(:effective_bg_color)
      end

      it "effective_bg_color prefers a nearer ancestor over a farther one" do
        root = Component.new
        leaf = Component.new
        leaf.send(:parent=, root)
        root.bg_color = 52
        leaf.bg_color = 22
        assert_equal Color.new(22), leaf.send(:effective_bg_color)
      end

      it "clear_background fills with the effective bg" do
        c = Component.new
        c.send(:rect=, Rect.new(0, 0, 2, 1))
        c.bg_color = 52
        c.send(:clear_background)
        assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "draw_text fills the effective bg behind spans that have none" do
        c = Component.new
        c.bg_color = 52
        c.send(:draw_text, 0, 0, StyledString.plain("hi"))
        assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "draw_text leaves an explicit span bg untouched" do
        c = Component.new
        c.bg_color = 52
        c.send(:draw_text, 0, 0, StyledString.styled("hi", bg: :red))
        assert_equal Color::RED, Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "draw_text does not fill when no bg is inherited" do
        c = Component.new
        c.send(:draw_text, 0, 0, StyledString.plain("hi"))
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
        assert_equal Color.palette(52), c.send(:effective_bg_color)
      end

      it "effective_bg_color tracks a theme swap without reassigning the Ref" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        c = Component.new
        c.bg_color = Theme.ref(:panel_bg)
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(22) })
        assert_equal Color.palette(22), c.send(:effective_bg_color)
      end

      it "resolves an ancestor's Theme::Ref for a descendant" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        root = Component.new
        leaf = Component.new
        leaf.send(:parent=, root)
        root.bg_color = Theme.ref(:panel_bg)
        assert_equal Color.palette(52), leaf.send(:effective_bg_color)
      end

      it "accepts a Theme::Ref to a built-in chrome token and resolves it live" do
        Screen.instance.theme = Theme::DARK
        c = Component.new
        c.bg_color = Theme.ref(:input_bg_color) # no custom token needed, no raise
        assert_equal Theme::DARK.input_bg_color, c.send(:effective_bg_color)
        Screen.instance.theme = Theme::LIGHT
        assert_equal Theme::LIGHT.input_bg_color, c.send(:effective_bg_color)
      end

      it "raises eagerly at assignment for an unknown token" do
        assert_raises(KeyError) { Component.new.bg_color = Theme.ref(:nonesuch) }
      end
    end

    context "#default_bg_color" do
      # A widget with an opinion of its own: the app has set nothing, yet the
      # component paints a surface and inheritance stops at it — which is what
      # keeps a field looking like a field inside a tinted panel.
      def welled(color = Color.new(52))
        Class.new(Component) { define_method(:default_bg_color) { color } }.new
      end

      it "is nil by default, so a plain component inherits" do
        assert_nil Component.new.send(:default_bg_color)
      end

      it "answers when the app has set no bg_color" do
        assert_equal Color.new(52), welled.send(:effective_bg_color)
      end

      it "terminates inheritance: an ancestor's tint does not strip the well" do
        panel = Component.new
        field = welled
        field.send(:parent=, panel)
        panel.bg_color = 22
        assert_equal Color.new(52), field.send(:effective_bg_color)
      end

      it "loses to the component's own bg_color — the whole of issue #11" do
        field = welled
        field.bg_color = 22
        assert_equal Color.new(22), field.send(:effective_bg_color)
      end

      it "falls through to the parent when it answers nil" do
        panel = Component.new
        leaf = Class.new(Component) { def default_bg_color = nil }.new
        leaf.send(:parent=, panel)
        panel.bg_color = 22
        assert_equal Color.new(22), leaf.send(:effective_bg_color)
      end

      # Outside its extent the widget is not there, so the dead tail takes what
      # surrounds it. Without this a one-row Select in a 25-row rect floods the
      # other 24 with its field well.
      it "does not color the dead tail outside the extent" do
        panel = Component::Layout::Absolute.new
        field = Class.new(Component) do
          define_method(:default_bg_color) { Color.new(52) }
          def extent = Size.new(4, 1)
        end.new
        panel.add(field)
        Screen.instance.content = panel
        panel.bg_color = 22
        panel.rect = Rect.new(0, 0, 8, 2)
        field.rect = Rect.new(0, 0, 8, 2)

        field.send(:clear_outside_extent)
        assert_equal Color.new(22), Screen.instance.buffer.cell(5, 0).style.bg
        assert_equal Color.new(22), Screen.instance.buffer.cell(0, 1).style.bg
      end

      it "does color the dead tail with an app-set bg_color, which is the widget's" do
        field = Class.new(Component) do
          define_method(:default_bg_color) { Color.new(52) }
          def extent = Size.new(4, 1)
        end.new
        Screen.instance.content = field
        field.bg_color = 22
        field.rect = Rect.new(0, 0, 8, 1)

        field.send(:clear_outside_extent)
        assert_equal Color.new(22), Screen.instance.buffer.cell(5, 0).style.bg
      end
    end

    context "BG_INHERIT" do
      def welled
        Class.new(Component) { def default_bg_color = Color.new(52) }.new
      end

      it "skips this component's own default and takes what surrounds it" do
        panel = Component.new
        field = welled
        field.send(:parent=, panel)
        panel.bg_color = 22
        field.bg_color = Component::BG_INHERIT
        assert_equal Color.new(22), field.send(:effective_bg_color)
      end

      # nil falls through to default_bg_color first; BG_INHERIT skips it. That
      # difference is the whole reason the sentinel exists.
      it "differs from nil, which consults the default first" do
        panel = Component.new
        field = welled
        field.send(:parent=, panel)
        panel.bg_color = 22
        assert_equal Color.new(52), field.send(:effective_bg_color)
      end

      it "yields the terminal default when nothing surrounds it" do
        assert_nil welled.tap { _1.bg_color = Component::BG_INHERIT }.send(:effective_bg_color)
      end

      it "reads back as assigned" do
        c = Component.new
        c.bg_color = Component::BG_INHERIT
        assert_equal Component::BG_INHERIT, c.bg_color
      end

      it "works as a state map entry" do
        panel = Component.new
        field = welled
        field.send(:parent=, panel)
        panel.bg_color = 22
        field.bg_color = { active: Component::BG_INHERIT }
        assert_equal Color.new(52), field.send(:effective_bg_color) # normal: its own well
        field.active = true
        assert_equal Color.new(22), field.send(:effective_bg_color) # active: the panel
      end

      # The dead tail asks the same question, so it must not paint :inherit.
      it "leaves the dead tail to what surrounds the widget" do
        panel = Component::Layout::Absolute.new
        field = Class.new(Component) do
          define_method(:default_bg_color) { Color.new(52) }
          def extent = Size.new(4, 1)
        end.new
        panel.add(field)
        Screen.instance.content = panel
        panel.bg_color = 22
        panel.rect = Rect.new(0, 0, 8, 1)
        field.rect = Rect.new(0, 0, 8, 1)
        field.bg_color = Component::BG_INHERIT

        field.send(:clear_outside_extent)
        assert_equal Color.new(22), Screen.instance.buffer.cell(5, 0).style.bg
      end
    end

    context "bg_color state map" do
      def welled
        Class.new(Component) { def default_bg_color = Color.new(52) }.new
      end

      it "picks the entry for the state the component is in" do
        c = Component.new
        c.bg_color = { normal: 22, active: 33 }
        assert_equal Color.new(22), c.send(:effective_bg_color)
        c.active = true
        assert_equal Color.new(33), c.send(:effective_bg_color)
      end

      it "coerces every entry, and reads back as a Hash" do
        c = Component.new
        c.bg_color = { normal: 22, active: Theme.ref(:input_bg_color) }
        assert_equal({ normal: Color.new(22), active: Theme.ref(:input_bg_color) }, c.bg_color)
      end

      it "resolves a Theme::Ref entry live" do
        Screen.instance.theme = Theme::DARK
        c = Component.new
        c.bg_color = { normal: Theme.ref(:input_bg_color) }
        assert_equal Theme::DARK.input_bg_color, c.send(:effective_bg_color)
        Screen.instance.theme = Theme::LIGHT
        assert_equal Theme::LIGHT.input_bg_color, c.send(:effective_bg_color)
      end

      # An absent key is not answered at this level at all, so resolution falls
      # through — which is what lets `{ active: … }` mean "keep my own well, but
      # override the focus shade".
      it "falls through to default_bg_color for an absent state" do
        c = welled
        c.bg_color = { active: 33 }
        assert_equal Color.new(52), c.send(:effective_bg_color)
        c.active = true
        assert_equal Color.new(33), c.send(:effective_bg_color)
      end

      it "falls through to the parent for an absent state" do
        panel = Component.new
        leaf = Component.new
        leaf.send(:parent=, panel)
        panel.bg_color = 22
        leaf.bg_color = { active: 33 }
        assert_equal Color.new(22), leaf.send(:effective_bg_color)
      end

      it "a flat color answers for every state — that is what makes it flat" do
        c = welled
        c.bg_color = 22
        c.active = true
        assert_equal Color.new(22), c.send(:effective_bg_color)
      end

      # The state set is closed and framework-defined: a key is added when Tuile
      # grows the state, never so an app can invent one.
      it "rejects a key outside BG_STATES at assignment" do
        e = assert_raises(ArgumentError) { Component.new.bg_color = { hover: 22 } }
        assert_includes e.message, "hover"
        assert_includes e.message, "normal, active"
      end

      it "validates a Theme::Ref entry eagerly" do
        assert_raises(KeyError) { Component.new.bg_color = { normal: Theme.ref(:nonesuch) } }
      end
    end

    context "#repaint default" do
      def container_with(children_rects)
        Component.new.tap do |container|
          children_rects.each do |r|
            kid = Component.new
            kid.rect = r
            container.send(:add_child, kid)
          end
        end
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

      # Marks every cell of `container`'s rect, so "did it clear?" is asserted on
      # the buffer rather than inferred from the invalidation set — the children
      # are re-invalidated either way.
      def mark(container)
        container.rect.height.times do |dy|
          Screen.instance.buffer.set_text(container.rect.left, container.rect.top + dy,
                                          StyledString.plain("#" * container.rect.width))
        end
        ["#" * container.rect.width] * container.rect.height
      end

      it "does not clear when children fully tile the rect" do
        container = container_with([Rect.new(0, 0, 5, 2)])
        container.send(:rect=, Rect.new(0, 0, 5, 2))
        marked = mark(container)
        container.repaint
        assert_equal marked, Screen.instance.buffer.region_text(container.rect)
      end

      it "re-invalidates its children even when they tile" do
        # The cascade must not dead-end here: a container that paints nothing of
        # its own redraws its area only through its children, and an ancestor's
        # clear_background has already wiped their cells.
        container = container_with([Rect.new(0, 0, 5, 2)])
        container.send(:rect=, Rect.new(0, 0, 5, 2))
        Screen.instance.invalidated_clear
        container.repaint
        assert Screen.instance.invalidated?(container.children.first)
      end

      it "treats overlapping siblings as tiling (sum >= area)" do
        # Two overlapping children together exceed the parent area; the
        # area-equality check should not false-positive a "gap" here.
        container = container_with([Rect.new(0, 0, 5, 2), Rect.new(0, 0, 5, 2)])
        container.send(:rect=, Rect.new(0, 0, 5, 2))
        marked = mark(container)
        container.repaint
        assert_equal marked, Screen.instance.buffer.region_text(container.rect)
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
        marked = mark(container)
        container.repaint
        assert_equal marked, Screen.instance.buffer.region_text(container.rect)
      end
    end

    it "cursor_position returns nil by default" do
      assert_nil Component.new.cursor_position
    end

    context "on_attached / on_detached" do
      # Records its own hook calls, so a spec can assert both that a hook fired
      # and what the tree looked like when it did.
      let(:spy_class) do
        Class.new(Component::Layout::Absolute) do
          attr_reader :events

          def initialize
            super
            @events = []
          end

          protected

          def on_attached = @events << [:attached, attached?]
          def on_detached = @events << [:detached, attached?]
        end
      end
      let(:spy) { spy_class.new }
      let(:pane) { Screen.instance.pane }

      it "fires across the whole subtree, parent before child" do
        parent = spy_class.new
        child = spy_class.new
        grandchild = spy_class.new
        child.add(grandchild)
        parent.add(child)
        order = []
        [parent, child, grandchild].each { |c| c.define_singleton_method(:on_attached) { order << c } }

        Screen.instance.content = parent

        assert_equal [parent, child, grandchild], order
      end

      it "fires nothing while the tree is detached, then fires for all of it" do
        parent = spy_class.new
        child = spy_class.new

        parent.add(child)
        assert_empty parent.events
        assert_empty child.events

        Screen.instance.content = parent
        assert_equal [[:attached, true]], parent.events
        assert_equal [[:attached, true]], child.events
      end

      it "reports attached? true in on_attached and false in on_detached" do
        layout = Component::Layout::Absolute.new
        layout.add(spy)
        Screen.instance.content = layout

        layout.remove(spy)

        assert_equal [[:attached, true], [:detached, false]], spy.events
      end

      it "fires detach then attach for a cross-container move" do
        a = Component::Layout::Absolute.new
        b = Component::Layout::Absolute.new
        pane.add_popup(Component::Popup.new(content: b))
        Screen.instance.content = a
        a.add(spy)
        spy.events.clear

        a.remove(spy)
        b.add(spy)

        assert_equal [[:detached, false], [:attached, true]], spy.events
      end

      it "fires nothing when attachedness doesn't change" do
        a = Component::Layout::Absolute.new
        Screen.instance.content = a
        a.add(spy)
        spy.events.clear

        a.remove(spy) # detached…
        a.add(spy)    # …and back
        spy.events.clear
        a.add(Component::Label.new) # unrelated churn in the same parent

        assert_empty spy.events
      end

      it "fires once per component even when a hook adds a child" do
        parent = spy_class.new
        late = spy_class.new
        parent.define_singleton_method(:on_attached) do
          @events << [:attached, attached?]
          add(late)
        end

        Screen.instance.content = parent

        assert_equal [[:attached, true]], parent.events
        assert_equal [[:attached, true]], late.events, "the late child must fire exactly once"
      end

      it "fires once per component even when a hook removes a child" do
        parent = spy_class.new
        doomed = spy_class.new
        parent.add(doomed)
        parent.define_singleton_method(:on_detached) do
          @events << [:detached, attached?]
          remove(doomed)
        end
        Screen.instance.content = parent
        doomed.events.clear

        pane.send(:remove_child, parent)

        assert_equal [[:detached, false]], doomed.events, "the removed child must fire exactly once"
      end

      it "runs on_detached before focus repair, with focus still inside the subtree" do
        spy.define_singleton_method(:focusable?) { true }
        layout = Component::Layout::Absolute.new
        layout.add(spy)
        Screen.instance.content = layout
        Screen.instance.focused = spy
        seen = nil
        spy.define_singleton_method(:on_detached) { seen = Screen.instance.focused }

        layout.remove(spy)

        assert_equal spy, seen, "focus repair must not have run yet"
        refute_equal spy, Screen.instance.focused, "…but it must run right after"
      end

      it "propagates a raising hook out of the container call" do
        spy.define_singleton_method(:on_attached) { raise "boom" }

        err = assert_raises(RuntimeError) { Screen.instance.content = spy }
        assert_equal "boom", err.message
      end

      it "fires for a component whose container is a slot rather than a list" do
        window = Component::Window.new("w")
        Screen.instance.content = window

        window.footer = spy
        assert_equal [[:attached, true]], spy.events

        window.footer = nil
        assert_equal [[:attached, true], [:detached, false]], spy.events
      end

      context "at Screen#close" do
        it "fires on_detached across the whole tree" do
          child = spy_class.new
          spy.add(child)
          Screen.instance.content = spy
          popup_body = spy_class.new
          pane.add_popup(Component::Popup.new(content: popup_body))
          [spy, child, popup_body].each { _1.events.clear }

          Screen.close

          assert_equal [[:detached, false]], spy.events
          assert_equal [[:detached, false]], child.events
          assert_equal [[:detached, false]], popup_body.events, "popups unmount too"
        end

        it "leaves nothing claiming to be attached" do
          Screen.instance.content = spy
          popup = Component::Popup.new
          pane.add_popup(popup)

          Screen.close

          refute spy.attached?
          refute popup.attached?, "popups unmount too"
          assert_empty pane.children
        end

        it "propagates a raising on_detached but still finishes closing" do
          spy.define_singleton_method(:on_detached) { raise "boom" }
          Screen.instance.content = spy
          screen = Screen.instance

          err = assert_raises(RuntimeError) { screen.close }

          assert_equal "boom", err.message
          assert_equal :closed, screen.state, "teardown must complete despite the raise"
          assert_raises(Tuile::Error) { Screen.instance } # the singleton slot is vacated
        end
      end

      it "cancels a ticker started in on_attached" do
        ticks = 0
        spy.define_singleton_method(:on_attached) do
          @ticker = Screen.instance.event_queue.tick_fps(10) { ticks += 1 }
        end
        spy.define_singleton_method(:on_detached) { @ticker.cancel }

        Screen.instance.content = spy
        Screen.instance.event_queue.tick_once
        assert_equal 1, ticks

        pane.send(:remove_child, spy)
        Screen.instance.event_queue.tick_once
        assert_equal 1, ticks, "the ticker must not fire after detach"
      end
    end

    context "final tree methods" do
      # The mechanism itself lives in Tuile::Final (and its spec); this pins the
      # six methods Component marks, since an override of any of them desyncs
      # the tree silently.
      it "admits an ordinary subclass" do
        Class.new(Component) { def focusable? = true }.new
      end

      it "rejects a subclass that redefines children" do
        klass = Class.new(Component) { def children = [] }
        e = assert_raises(Error) { klass.new }
        assert_includes e.message, "children"
        assert_includes e.message, "Tuile::Component#children"
      end

      it "rejects a redefined parent pointer, however protected" do
        klass = Class.new(Component) do
          protected def parent=(_new_parent); end
        end
        e = assert_raises(Error) { klass.new }
        assert_includes e.message, "parent="
      end

      it "rejects an override arriving through an included module" do
        sneaky = Module.new { def add_child(_child, at: nil); end }
        klass = Class.new(Component) { include sneaky }
        e = assert_raises(Error) { klass.new }
        assert_includes e.message, "add_child"
      end

      it "rejects an override arriving through a prepend" do
        sneaky = Module.new { def detach_child(_child); end }
        klass = Class.new(Component) { prepend sneaky }
        e = assert_raises(Error) { klass.new }
        assert_includes e.message, "detach_child"
      end

      it "names every offending method at once" do
        klass = Class.new(Component) do
          def children = []
          def remove_child(_child); end
        end
        e = assert_raises(Error) { klass.new }
        assert_includes e.message, "children, remove_child"
      end
    end

    context "the tree API" do
      # D_tree_api: `attached?` walks the parent chain while a subtree walk uses
      # `children`, so the two must never be able to disagree. This exercises
      # every container kind in one tree — ScreenPane (slot + list + chrome),
      # Layout (plain list), HasContent (single slot) and Window (slot + footer).
      it "keeps children, @children and the parent pointers in agreement" do
        window = Component::Window.new("w")
        window.content = Component::List.new
        window.footer = Component::TextField.new
        layout = Component::Layout::Absolute.new
        layout.add(window)
        layout.add(Component::Label.new)
        Screen.instance.content = layout
        popup = Component::Popup.new(content: Component::Button.new("ok"))
        Screen.instance.add_popup(popup)

        Screen.instance.pane.on_tree do |c|
          assert_equal c.children, c.instance_variable_get(:@children),
                       "#{c.class} derives #children instead of owning it"
          c.children.each do |kid|
            assert_equal c, kid.parent, "#{kid.class} listed by #{c.class} has a different parent"
          end
        end
      end

      it "orders a Window's own children content-then-footer, whichever is set first" do
        footer_first = Component::Window.new("a")
        footer_first.footer = Component::Label.new
        footer_first.content = Component::List.new

        content_first = Component::Window.new("b")
        content_first.content = Component::List.new
        content_first.footer = Component::Label.new

        # The footer slot is wired at construction, so the order now holds
        # structurally rather than by the insert index each setter picks.
        assert_equal [footer_first.content, footer_first.footer.parent], footer_first.children
        assert_equal [content_first.content, content_first.footer.parent], content_first.children
      end
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

      it "is answerable with no Screen in the process at all" do
        Screen.close # the predicate must not reach for the singleton
        layout = Component::Layout::Absolute.new
        label = Component::Label.new

        layout.add(label) # must not raise "Screen not initialized"
        assert !layout.attached?
        assert !label.attached?
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

    # `D_visibility`. The flag means *gone*: as if detached, but still in the
    # tree — so the assertions come in pairs, one that the user can't reach it
    # and one that the component kept what a detach would have cost it.
    context "visible" do
      def tab_stop
        Class.new(Component) do
          def focusable? = true
          def tab_stop? = true
        end.new
      end

      # @return [Array(Component::Layout::Vertical, Component, Component)] an
      #   attached, sized form of two tab stops.
      def form
        screen = Screen.instance
        box = Component::Layout::Vertical.new
        first = tab_stop
        second = tab_stop
        box.add([first, second], Component::Layout::Fixed[1])
        screen.content = box
        box.rect = Rect.new(0, 0, 20, 4)
        [box, first, second]
      end

      it "defaults to true" do
        assert_predicate Component.new, :visible?
      end

      it "coerces to a boolean and ignores a no-op assignment" do
        c = Component.new
        c.visible = nil
        refute_predicate c, :visible?
        c.visible = 0 # truthy in Ruby
        assert_predicate c, :visible?
      end

      it "drops a hidden component out of the Tab cycle" do
        box, first, second = form
        Screen.instance.focused = first

        second.visible = false
        Screen.instance.send(:cycle_focus, forward: true)
        assert_equal first, Screen.instance.focused, "Tab landed on a hidden component"

        second.visible = true
        Screen.instance.send(:cycle_focus, forward: true)
        assert_equal second, Screen.instance.focused
        assert_equal box, second.parent
      end

      # The ancestor case is the one a per-component `visible?` test misses,
      # and it is why every reachability walk goes through on_shown_tree.
      it "drops a shown component under a hidden ancestor out of the Tab cycle" do
        screen = Screen.instance
        outer = Component::Layout::Vertical.new
        panel = Component::Layout::Vertical.new
        leaf = tab_stop
        panel.add(leaf, Component::Layout::Fixed[1])
        anchor = tab_stop
        outer.add([anchor, panel], Component::Layout::Fixed[1])
        screen.content = outer
        outer.rect = Rect.new(0, 0, 20, 4)
        screen.focused = anchor

        panel.visible = false
        assert_predicate leaf, :visible?, "the leaf's own flag is untouched"
        screen.send(:cycle_focus, forward: true)
        assert_equal anchor, screen.focused
      end

      it "fires no lifecycle hook, and keeps the parent and the rect" do
        box, _first, second = form
        rect = second.rect
        fired = []
        second.define_singleton_method(:on_detached) { fired << :detached }
        second.define_singleton_method(:on_attached) { fired << :attached }

        second.visible = false
        second.visible = true
        assert_empty fired
        assert_equal box, second.parent
        assert_predicate second, :attached?
        assert_equal rect, second.rect
      end

      context "focus repair" do
        it "hands focus to the parent, which cascades to a shown tab stop" do
          _box, first, second = form
          Screen.instance.focused = second

          second.visible = false
          assert_equal first, Screen.instance.focused
        end

        # Never nil: with no focus, ScreenPane#focus_chain returns nil and
        # bubble_key delivers to nobody — so an unhandled `q` would fall through
        # to the event loop and quit the app.
        it "never leaves focus nil while something is still showing" do
          _box, first, second = form
          Screen.instance.focused = second

          second.visible = false
          refute_nil Screen.instance.focused
          assert_predicate first, :visible?
        end

        it "repairs from a descendant of the hidden subtree" do
          screen = Screen.instance
          outer = Component::Layout::Vertical.new
          anchor = tab_stop
          panel = Component::Layout::Vertical.new
          leaf = tab_stop
          panel.add(leaf, Component::Layout::Fixed[1])
          outer.add([anchor, panel], Component::Layout::Fixed[1])
          screen.content = outer
          outer.rect = Rect.new(0, 0, 20, 4)
          screen.focused = leaf

          panel.visible = false
          assert_equal anchor, screen.focused
        end

        it "leaves focus alone when it sits outside the hidden subtree" do
          _box, first, second = form
          Screen.instance.focused = first

          second.visible = false
          assert_equal first, Screen.instance.focused
        end

        it "does not restore focus when the component comes back" do
          _box, first, second = form
          Screen.instance.focused = second

          second.visible = false
          second.visible = true
          assert_equal first, Screen.instance.focused
        end
      end

      context "Screen#focused=" do
        it "refuses a hidden component" do
          _box, _first, second = form
          second.visible = false
          assert_raises(Tuile::Error) { Screen.instance.focused = second }
        end

        it "refuses a shown component under a hidden ancestor" do
          screen = Screen.instance
          panel = Component::Layout::Vertical.new
          leaf = tab_stop
          panel.add(leaf, Component::Layout::Fixed[1])
          screen.content = panel
          panel.rect = Rect.new(0, 0, 20, 4)

          panel.visible = false
          assert_raises(Tuile::Error) { screen.focused = leaf }
        end
      end

      context "painting" do
        it "counts a hidden child's cells as a gap, so the parent blanks them" do
          screen = Screen.instance
          box = Component::Layout::Vertical.new
          label = Component::Label.new("VISIBLE")
          box.add(label, Component::Layout::Percent[100])
          screen.content = box
          box.rect = Rect.new(0, 0, 20, 1)
          screen.repaint
          assert_includes screen.buffer.row_text(0), "VISIBLE"

          label.visible = false
          screen.repaint
          refute_includes screen.buffer.row_text(0), "VISIBLE"
        end

        it "paints again, unchanged, when shown" do
          screen = Screen.instance
          box = Component::Layout::Vertical.new
          label = Component::Label.new("VISIBLE")
          box.add(label, Component::Layout::Percent[100])
          screen.content = box
          box.rect = Rect.new(0, 0, 20, 1)
          screen.repaint
          before = screen.buffer.row_text(0)

          label.visible = false
          screen.repaint
          label.visible = true
          screen.repaint
          assert_equal before, screen.buffer.row_text(0)
        end
      end

      context "mouse" do
        it "routes no click into a hidden child" do
          screen = Screen.instance
          layout = Component::Layout::Absolute.new
          child = tab_stop
          layout.add(child)
          screen.content = layout
          layout.rect = Rect.new(0, 0, 20, 4)
          child.rect = Rect.new(0, 0, 20, 1)

          child.visible = false
          screen.send(:handle_mouse, MouseEvent.new(:left, 1, 0))
          refute_equal child, screen.focused
        end
      end

      context "#inspect" do
        it "says hidden, and says nothing when shown" do
          c = Component.new
          refute_includes c.inspect, "hidden"
          c.visible = false
          assert_includes c.inspect, "hidden"
        end
      end
    end

    context "#on_theme_changed" do
      it "is protected — plumbing Screen sends to, never public API" do
        assert Component.protected_method_defined?(:on_theme_changed)
        assert Component.public_method_defined?(:on_theme_changed=)
      end

      it "is a no-op by default" do
        Component.new.send(:on_theme_changed)
      end

      it "fires the assigned listener" do
        c = Component.new
        fired = 0
        c.on_theme_changed = -> { fired += 1 }
        c.send(:on_theme_changed)
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
        c.send(:on_theme_changed)
        assert_equal 1, c.hook_calls
        assert_equal 1, fired
      end
    end

    context "#on_blur" do
      it "is protected — plumbing Screen sends to, never public API" do
        assert Component.protected_method_defined?(:on_blur)
      end

      it "is a no-op by default" do
        Component.new.send(:on_blur)
      end

      it "leaves on_focus public: three mixins override it as a composition seam" do
        assert Component.public_method_defined?(:on_focus)
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
