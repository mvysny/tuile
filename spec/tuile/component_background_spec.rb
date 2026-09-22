# frozen_string_literal: true

module Tuile
  describe ComponentBackground do
    before { Screen.fake }
    after { Screen.close }

    def bg(component) = component.send(:bg)
    def effective(component) = bg(component).effective

    # A widget with an opinion of its own: the app has set nothing, yet the
    # component paints a surface and inheritance stops at it — which is what
    # keeps a field looking like a field inside a tinted panel.
    def welled(color = 52)
      Component.new.tap { bg(_1).default_color = color }
    end

    def under(panel, child)
      child.send(:parent=, panel)
      child
    end

    context "#effective" do
      it "is the component's own color when set" do
        c = Component.new
        c.bg_color = 52
        assert_equal Color.new(52), effective(c)
      end

      it "is nil when nothing is set anywhere" do
        assert_nil effective(Component.new)
      end

      it "inherits the nearest ancestor's color" do
        root = Component.new
        leaf = under(under(root, Component.new), Component.new)
        root.bg_color = 52
        assert_equal Color.new(52), effective(leaf)
      end

      it "prefers a nearer ancestor over a farther one" do
        root = Component.new
        leaf = under(root, Component.new)
        root.bg_color = 52
        leaf.bg_color = 22
        assert_equal Color.new(22), effective(leaf)
      end

      it "resolves a Theme::Ref against the current theme" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        c = Component.new
        c.bg_color = Theme.ref(:panel_bg)
        assert_equal Color.palette(52), effective(c)
      end

      it "tracks a theme swap without reassigning the Ref" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        c = Component.new
        c.bg_color = Theme.ref(:panel_bg)
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(22) })
        assert_equal Color.palette(22), effective(c)
      end

      it "resolves an ancestor's Theme::Ref for a descendant" do
        Screen.instance.theme = Theme::DARK.with(custom: { panel_bg: Color.palette(52) })
        root = Component.new
        leaf = under(root, Component.new)
        root.bg_color = Theme.ref(:panel_bg)
        assert_equal Color.palette(52), effective(leaf)
      end

      it "resolves a Theme::Ref to a built-in chrome token live" do
        Screen.instance.theme = Theme::DARK
        c = Component.new
        c.bg_color = Theme.ref(:input_bg_color) # no custom token needed, no raise
        assert_equal Theme::DARK.input_bg_color, effective(c)
        Screen.instance.theme = Theme::LIGHT
        assert_equal Theme::LIGHT.input_bg_color, effective(c)
      end
    end

    context "#default_color" do
      it "is nil by default, so a plain component inherits" do
        assert_nil bg(Component.new).default_color
      end

      it "answers when the app has set no bg_color" do
        assert_equal Color.new(52), effective(welled)
      end

      it "terminates inheritance: an ancestor's tint does not strip the well" do
        panel = Component.new
        field = under(panel, welled)
        panel.bg_color = 22
        assert_equal Color.new(52), effective(field)
      end

      it "loses to the component's own bg_color — the whole of issue #11" do
        field = welled
        field.bg_color = 22
        assert_equal Color.new(22), effective(field)
      end

      it "coerces and validates exactly as bg_color= does" do
        assert_equal({ normal: Color.new(22) }, bg(welled({ normal: 22 })).default_color)
        assert_raises(ArgumentError) { welled({ hover: 22 }) }
        assert_raises(KeyError) { welled(Theme.ref(:nonesuch)) }
      end

      # The field wells are set in constructors, and a tree assembles with no
      # screen in the process — so a chrome token must validate without one.
      it "accepts a chrome-token Ref with no screen" do
        Screen.close
        assert_equal ComponentBackground::INPUT_WELL, bg(welled(ComponentBackground::INPUT_WELL)).default_color
      ensure
        Screen.fake
      end

      it "invalidates the attached subtree, since descendants inherit it" do
        panel = Component::Layout::Absolute.new
        leaf = Component.new
        panel.add(leaf)
        mount_at(panel, Rect.new(0, 0, 4, 1))
        Screen.instance.invalidated_clear
        bg(panel).default_color = 52
        assert Screen.instance.invalidated?(leaf)
      end

      # Outside its extent the widget is not there, so the dead tail takes what
      # surrounds it. Without this a one-row Select in a 25-row rect floods the
      # other 24 with its field well.
      it "does not color the dead tail outside the extent" do
        panel = Component::Layout::Absolute.new
        field = Class.new(Component) { def extent = Size.new(4, 1) }.new
        bg(field).default_color = 52
        panel.add(field)
        panel.bg_color = 22
        mount_at(panel, Rect.new(0, 0, 8, 2))
        Testing.place(field, Rect.new(0, 0, 8, 2))

        field.send(:clear_outside_extent, Screen.instance.canvas)
        assert_equal Color.new(22), Screen.instance.buffer.cell(5, 0).style.bg
        assert_equal Color.new(22), Screen.instance.buffer.cell(0, 1).style.bg
      end

      it "does color the dead tail with an app-set bg_color, which is the widget's" do
        field = Class.new(Component) { def extent = Size.new(4, 1) }.new
        bg(field).default_color = 52
        field.bg_color = 22
        mount_at(field, Rect.new(0, 0, 8, 1))

        field.send(:clear_outside_extent, Screen.instance.canvas)
        assert_equal Color.new(22), Screen.instance.buffer.cell(5, 0).style.bg
      end
    end

    context "INHERIT" do
      it "skips this component's own default and takes what surrounds it" do
        panel = Component.new
        field = under(panel, welled)
        panel.bg_color = 22
        field.bg_color = ComponentBackground::INHERIT
        assert_equal Color.new(22), effective(field)
      end

      # nil falls through to default_color first; INHERIT skips it. That
      # difference is the whole reason the sentinel exists.
      it "differs from nil, which consults the default first" do
        panel = Component.new
        field = under(panel, welled)
        panel.bg_color = 22
        assert_equal Color.new(52), effective(field)
      end

      # The chain walks the ancestors, not the parent — the rule this replaced
      # sniffed `parent.is_a?(HasValue)` and broke the moment a container sat
      # between a composed widget and its INHERIT face.
      it "reaches past an intervening container to the surrounding well" do
        composer = Component::Layout::Absolute.new
        middle = Component::Layout::Absolute.new
        field = welled
        composer.add(middle)
        middle.add(field)
        composer.bg_color = 22
        field.bg_color = ComponentBackground::INHERIT

        assert_equal Color.new(22), effective(field)
      end

      it "yields the terminal default when nothing surrounds it" do
        assert_nil effective(welled.tap { _1.bg_color = ComponentBackground::INHERIT })
      end

      it "reads back as assigned" do
        c = Component.new
        c.bg_color = ComponentBackground::INHERIT
        assert_equal ComponentBackground::INHERIT, c.bg_color
      end

      it "works as a state map entry" do
        panel = Component.new
        field = under(panel, welled)
        panel.bg_color = 22
        field.bg_color = { active: ComponentBackground::INHERIT }
        assert_equal Color.new(52), effective(field) # normal: its own well
        field.active = true
        assert_equal Color.new(22), effective(field) # active: the panel
      end

      # The dead tail asks the same question, so it must not paint :inherit.
      it "leaves the dead tail to what surrounds the widget" do
        panel = Component::Layout::Absolute.new
        field = Class.new(Component) { def extent = Size.new(4, 1) }.new
        bg(field).default_color = 52
        panel.add(field)
        panel.bg_color = 22
        mount_at(panel, Rect.new(0, 0, 8, 1))
        Testing.place(field, Rect.new(0, 0, 8, 1))
        field.bg_color = ComponentBackground::INHERIT

        field.send(:clear_outside_extent, Screen.instance.canvas)
        assert_equal Color.new(22), Screen.instance.buffer.cell(5, 0).style.bg
      end
    end

    context "state map" do
      it "picks the entry for the state the component is in" do
        c = Component.new
        c.bg_color = { normal: 22, active: 33 }
        assert_equal Color.new(22), effective(c)
        c.active = true
        assert_equal Color.new(33), effective(c)
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
        assert_equal Theme::DARK.input_bg_color, effective(c)
        Screen.instance.theme = Theme::LIGHT
        assert_equal Theme::LIGHT.input_bg_color, effective(c)
      end

      # An absent key is not answered at this level at all, so resolution falls
      # through — which is what lets `{ active: … }` mean "keep my own well, but
      # override the focus shade".
      it "falls through to default_color for an absent state" do
        c = welled
        c.bg_color = { active: 33 }
        assert_equal Color.new(52), effective(c)
        c.active = true
        assert_equal Color.new(33), effective(c)
      end

      it "falls through to the parent for an absent state" do
        panel = Component.new
        leaf = under(panel, Component.new)
        panel.bg_color = 22
        leaf.bg_color = { active: 33 }
        assert_equal Color.new(22), effective(leaf)
      end

      it "a flat color answers for every state — that is what makes it flat" do
        c = welled
        c.bg_color = 22
        c.active = true
        assert_equal Color.new(22), effective(c)
      end

      # The state set is closed and framework-defined: a key is added when Tuile
      # grows the state, never so an app can invent one.
      it "rejects a key outside STATES at assignment" do
        e = assert_raises(ArgumentError) { Component.new.bg_color = { hover: 22 } }
        assert_includes e.message, "hover"
        assert_includes e.message, "normal, active"
      end

      it "validates a Theme::Ref entry eagerly" do
        assert_raises(KeyError) { Component.new.bg_color = { normal: Theme.ref(:nonesuch) } }
      end
    end

    context "INPUT_WELL" do
      it "is the input well at rest and the focus shade while active" do
        c = welled(ComponentBackground::INPUT_WELL)
        assert_equal Theme::DARK.input_bg_color, effective(c)
        c.active = true
        assert_equal Theme::DARK.active_bg_color, effective(c)
      end
    end
  end
end
