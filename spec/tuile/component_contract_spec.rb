# frozen_string_literal: true

module Tuile
  # The contract suite: invariants *every* component owes the framework, run
  # over a catalog of every concrete {Component} subclass rather than one class
  # at a time. Its reason to exist is the components that do not exist yet — a
  # new widget is enrolled the moment it is catalogued, and the completeness
  # guard below makes catalogued mandatory.
  #
  # Each invariant here is one AGENTS.md rule that (a) applies to every
  # component, (b) nothing enforces at runtime, and (c) fails *silently* — no
  # exception, and a per-component spec that asserts what the widget paints
  # still passes. Per-widget behavior stays in `<widget>_spec.rb`; only
  # framework-wide obligations belong here.
  describe "component contract" do
    before { Screen.fake }
    after { Screen.close }

    # Methods rather than constants: a constant assigned inside a block lands in
    # the enclosing `module Tuile`, where it would shadow a Zeitwerk-managed name.

    # @return [Rect] what every catalogued component is handed — inset from the
    #   screen, so the paint-outside check has margin on all four sides.
    def contract_rect = Rect.new(4, 3, 40, 9)

    # @return [String] a glyph no component paints, laid over the whole buffer so
    #   anything a component writes stands out against it.
    def sentinel = "·"

    # Every concrete component, with a factory returning one populated enough to
    # paint something. Factories rather than instances: each example gets a
    # fresh tree, on a fresh {FakeScreen}.
    #
    # A local, for the same reason.
    catalog = {
      Component => -> { Component.new },
      Component::Label => -> { Component::Label.new("label text") },
      Component::Button => -> { Component::Button.new("Save") },
      Component::Checkbox => -> { Component::Checkbox.new("Enabled", value: true) },
      Component::CheckboxGroup => -> { Component::CheckboxGroup.new(items: %w[one two three]) },
      Component::RadioGroup => -> { Component::RadioGroup.new(items: %w[one two three], value: "two") },
      Component::Select => -> { Component::Select.new(items: %w[one two three], value: "two") },
      Component::ComboBox => -> { Component::ComboBox.new(items: %w[one two three]) },
      # Scrollbar on here and on {Component::TextView} below: `:gone` (the
      # default) leaves the bar at an empty rect forever, so
      # `places_children?` answers false and every container check below
      # quietly skips the one child each of them has.
      Component::List => lambda {
        Component::List.new.tap do |l|
          l.lines = %w[one two three]
          l.scrollbar_visibility = :visible
        end
      },
      Component::ListDropdown => -> { Component::ListDropdown.new.tap { _1.items = %w[one two] } },
      Component::ListDropdown::Menu => -> { Component::ListDropdown::Menu.new.tap { _1.items = %w[one two] } },
      Component::Slot => -> { Component::Slot.new(Component::Label.new("in a slot")) },
      Component::Scroller => lambda {
        Component::Scroller.new(Component::Label.new("scrolled content"), content_rows: 20)
      },
      Component::FormItem => lambda {
        Component::FormItem.new(Component::TextField.new, caption: "Username", required: true)
      },
      Component::FormLayout => lambda {
        Component::FormLayout.new.tap do |form|
          form.add(Component::TextField.new, caption: "Username", required: true)
          form.add(Component::Button.new("Save"))
        end
      },
      Component::Layout::Absolute => -> { populated_absolute },
      Component::Layout::Vertical => -> { populated_box(Component::Layout::Vertical.new(spacing: 1)) },
      Component::Layout::Horizontal => -> { populated_box(Component::Layout::Horizontal.new(spacing: 1)) },
      Component::TextField => -> { Component::TextField.new.tap { _1.value = "typed" } },
      Component::PasswordField => -> { Component::PasswordField.new.tap { _1.value = "secret" } },
      Component::TextArea => -> { Component::TextArea.new.tap { _1.value = "two\nlines" } },
      Component::TextView => lambda {
        Component::TextView.new.tap do |tv|
          tv.text = "some prose to wrap"
          tv.scrollbar_visibility = :visible
        end
      },
      Component::LogTextView => -> { Component::LogTextView.new.tap { _1.log("a log row") } },
      Component::IntegerField => -> { Component::IntegerField.new.tap { _1.value = 42 } },
      Component::FloatField => -> { Component::FloatField.new.tap { _1.value = 1.5 } },
      Component::BigDecimalField => -> { Component::BigDecimalField.new.tap { _1.value = BigDecimal("1.5") } },
      Component::DateField => -> { Component::DateField.new.tap { _1.value = Date.new(2026, 9, 4) } },
      Component::TimeField => -> { Component::TimeField.new.tap { _1.set_to(13, 45) } },
      Component::DateTimeField => lambda {
        Component::DateTimeField.new.tap { _1.value = DateTime.new(2026, 9, 14, 13, 45) }
      },
      Component::ProgressBar => -> { Component::ProgressBar.new(value: 40) },
      Component::Fill => -> { Component::Fill.new("│", color: :bright_black) },
      Component::VerticalScrollBar => -> { Component::VerticalScrollBar.new(row_count: 40, scroll_top_row: 4) },
      Component::Tabs => -> { Component::Tabs.new.tap { |t| %w[One Two].each { t.add_tab(_1) } } },
      Component::TabSheet => -> { populated_tab_sheet },
      Component::MenuBar => -> { Component::MenuBar.new.tap { |b| %w[File Edit].each { b.add_item(_1) } } },
      Component::Window => -> { Component::Window.new("Caption").tap { _1.content = Component::Label.new("body") } },
      Component::LogWindow => -> { Component::LogWindow.new("Log") },
      Component::InfoWindow => -> { Component::InfoWindow.new("Info", "the body prose") },
      Component::PickerWindow => -> { Component::PickerWindow.new("Pick", [%w[a Apple], %w[b Banana]]) { nil } },
      Component::Overlay => -> { Component::Overlay.new(content: Component::Label.new("floating")) },
      Component::Popup => -> { Component::Popup.new(content: Component::Label.new("modal")) },
      Component::ConfirmWindow => -> { Component::ConfirmWindow.new("Sure?").tap { _1.message = "Really?" } },
      Component::Notification => -> { Component::Notification.show("Saved") },
      Component::Notification::View => -> { Component::Notification::View.new.tap { _1.text = "Saved" } }
    }

    # Deliberately uncatalogued, each with the reason. The completeness guard
    # reads this, so a new component cannot opt out by being forgotten.
    excluded = {
      Component::Layout => "abstract: the base to subclass with a relayout; a bare one places nothing",
      Component::Layout::Box => "abstract: main_extent / cross_extent / build_rect raise",
      Component::AbstractStringField => "abstract: the base of TextField / TextArea, never instantiated",
      Component::AbstractWrappingField => "abstract: needs an editor, and defines no value",
      Component::IntegerField::Field => "private machinery: covered through IntegerField",
      Component::FloatField::Field => "private machinery: covered through FloatField",
      Component::BigDecimalField::Field => "private machinery: covered through BigDecimalField",
      Component::ConfirmWindow.const_get(:MeasuredPopup) => "private machinery: via ConfirmWindow",
      ScreenPane => "the structural root: Screen owns the only instance; see screen_pane_spec"
    }

    # @return [Component::Layout::Absolute] two children filling {#contract_rect}.
    def populated_absolute
      layout = Component::Layout::Absolute.new
      r = contract_rect
      half = r.width / 2
      layout.add(Component::Label.new("left"), Rect.new(0, 0, half, r.height))
      layout.add(Component::Label.new("right"), Rect.new(half, 0, r.width - half, r.height))
      layout
    end

    # @param box [Component::Layout::Box]
    # @return [Component::Layout::Box] `box` with one fixed and one expanding child.
    def populated_box(box)
      box.add(Component::Label.new("fixed"), Component::Layout::Fixed[2])
      box.add(Component::Label.new("expanding"), Component::Layout::Expand[1])
      box
    end

    # @return [Component::TabSheet] two tabs, the first selected.
    def populated_tab_sheet
      sheet = Component::TabSheet.new
      sheet.add_tab("One", Component::Label.new("pane one"))
      sheet.add_tab("Two", Component::Label.new("pane two"))
      sheet
    end

    # Lays `component` out at {#contract_rect} over a sentinel-filled buffer, as the
    # screen would: attached (so `invalidate` lands), sized, painted.
    # @param component [Component]
    # @return [Buffer] the screen's buffer, painted.
    def paint(component)
      screen = Screen.instance
      place(component, contract_rect)
      screen.buffer.clear(StyledString::Style::DEFAULT)
      screen.buffer.fill(Rect.new(0, 0, screen.size.width, screen.size.height),
                         StyledString::Style::DEFAULT)
      fill_sentinel(screen.buffer)
      repaint(component)
      screen.buffer
    end

    # Mounts `component` at `rect` under an {Component::Layout::Absolute}, or
    # moves it there if it is mounted already. Straight onto `screen.content`
    # it would not keep the rect: the pane hands its content the whole screen
    # at the next settle, swallowing the margin the stray sweep needs.
    #
    # An {Component::Overlay} opens at `rect` instead: the popup stack is the
    # only parent one accepts ({Component#add_child}).
    # @param component [Component]
    # @param rect [Rect]
    # @return [void]
    def place(component, rect)
      case component.parent
      when nil
        if component.is_a?(Component::Overlay)
          component.open(Component::Overlay::At[rect])
        else
          holder = Component::Layout::Absolute.new
          holder.add(component, rect)
          Screen.instance.content = holder
        end
      when ScreenPane then component.placement = Component::Overlay::At[rect]
      else component.parent.constrain(component, rect)
      end
      Screen.instance.flush_layout
    end

    # {#paint} with the clip taken off: the same canvas, rebuilt with
    # `clip: nil`. See the stray sweep below for why it needs one.
    # @param component [Component]
    # @return [Buffer] the screen's buffer, painted with no clip in force.
    def paint_unclipped(component)
      paint(component)
      fill_sentinel(Screen.instance.buffer)
      clipped = Screen.instance.canvas_for(component)
      component.repaint(Canvas.new(Screen.instance.buffer,
                                   bg_color: clipped.bg_color, origin: clipped.origin, clip: nil))
      Screen.instance.buffer
    end

    # @param buffer [Buffer]
    # @return [void]
    def fill_sentinel(buffer)
      buffer.height.times { |y| buffer.width.times { |x| buffer.set_char(x, y, sentinel) } }
    end

    # Whether `component` assigns its descendants' rects from its own size — an
    # {Component::Layout::Absolute} does not, and owes no propagation.
    #
    # It probes by **resizing**, not by moving: a `rect` is parent-relative, so
    # sliding a container sideways leaves every descendant's rect untouched by
    # design, and a move would report every container in the catalog as placing
    # nothing (`D_relative_rect`).
    #
    # The `flush_layout` is load-bearing: layout is deferred
    # (`D_deferred_layout`), so without it the probe reads the rects it just
    # dirtied, answers `false`, and every caller quietly `skip`s — which is how
    # `Layout::Vertical`, `Layout::Horizontal` and `DateTimeField` once went
    # pending without a single failure.
    # @param component [Component] already laid out at {#contract_rect}.
    # @return [Boolean]
    def places_children?(component)
      before = descendant_rects(component)
      r = contract_rect
      place(component, Rect.new(r.left, r.top, r.width - 1, r.height - 1))
      before != descendant_rects(component)
    end

    # @param component [Component]
    # @return [Array<Rect>] every descendant's rect, self excluded.
    def descendant_rects(component)
      rects = []
      component.walk_tree { rects << _1.rect unless _1.equal?(component) }
      rects
    end

    # @param buffer [Buffer]
    # @param rect [Rect]
    # @return [Array<Array(Integer, Integer, String)>] every cell outside `rect`
    #   whose glyph is no longer the sentinel.
    def cells_outside(buffer, rect)
      out = []
      buffer.height.times do |y|
        buffer.width.times do |x|
          next if rect.contains?(Point.new(x, y))

          glyph = buffer.cell(x, y).grapheme
          out << [x, y, glyph] unless glyph == sentinel || glyph.empty?
        end
      end
      out
    end

    context "the catalog itself" do
      it "covers every Component subclass, so a new component cannot opt out silently" do
        # Zeitwerk loads on first reference, so without this the guard would see
        # only what the catalog itself named — i.e. it could never spot the new
        # component it exists to spot. BigDecimalField is `do_not_eager_load`, so
        # it needs the explicit nudge.
        Zeitwerk::Loader.eager_load_all
        assert Component.const_defined?(:BigDecimalField)
        known = catalog.keys + excluded.keys
        # Three kinds of subclass are not the gem's to catalog, and a full-suite
        # run manufactures all three: a spec's `define_singleton_method(:repaint)`
        # leaves a singleton class, an app subclasses components (the sampler),
        # and an anonymous `Class.new` has no name to report.
        found = ObjectSpace.each_object(Class).select do |c|
          c <= Component && !c.singleton_class? && c.name&.start_with?("Tuile::")
        end
        missing = found - known
        assert_empty missing, "add these to the catalog, or to `excluded` with a reason: #{missing.inspect}"
      end

      it "excludes nothing it also catalogs" do
        assert_empty catalog.keys & excluded.keys
      end

      it "builds every catalogued component" do
        catalog.each { |klass, factory| assert_kind_of klass, instance_exec(&factory) }
      end
    end

    # AGENTS.md, Repaint: "A component must not draw outside its `rect`."
    # `Screen#canvas_for` enforces it, so an overrun reaches no *neighbour* — but
    # it is still a bug, showing as the component looking truncated for no reason
    # its own spec can explain. Hence {#paint_unclipped}: through the enforcement
    # the strays never reach the buffer and this could never fail (`D_clip`).
    context "paints only inside its rect" do
      catalog.each_key do |klass|
        it klass.name do
          component = instance_exec(&catalog[klass])
          buffer = paint_unclipped(component)
          # An overlay places itself; ask where it actually landed.
          strays = cells_outside(buffer, component.rect)
          assert_empty strays.first(10), "#{klass} painted outside #{component.rect.inspect}"
        end
      end
    end

    # AGENTS.md, Repaint: "Never blank a cell you are about to
    # paint over — that is what makes the minimal diff minimal." A component
    # that clears and then repaints the same glyph marks the cell dirty anyway,
    # so `flush` re-emits it. Invisible on screen and silent under every
    # per-widget spec, which is why it needs a mechanical check: `D_progress_bar`
    # measured a ProgressBar re-emitting its whole row five times a second.
    #
    # Note this asks nothing of a component's *children* — only the component
    # itself repaints here — so a gap-clearing container wiping its descendants'
    # cells (`D_repaint_cascade`, deliberate) does not register.
    context "an unchanged repaint emits nothing" do
      # Nothing is exempt today. Should a component ever have to be, mark it
      # `pending` with the reason and never `skip`: fixing it then fails the
      # example, which is the reminder to delete the entry — that is how the
      # Window family's 925-byte border re-emission got closed rather than
      # settling in as a documented quirk.
      catalog.each_key do |klass|
        it klass.name do
          component = instance_exec(&catalog[klass])
          buffer = paint(component)
          buffer.flush
          Testing.paint(component)
          assert_equal "", buffer.flush, "#{klass} re-emitted cells it had already painted"
        end
      end
    end

    # AGENTS.md, Layout: a container assigns every child a rect on
    # every pass, including when its own rect is empty — otherwise the children
    # keep the coordinates they last had and the next full repaint paints them
    # there (`D_empty_ancestor`). Only the drain filter's backstop keeps that
    # inert, and it is a backstop: the empty rect is also what makes a collapsed
    # field's `cursor_position` answer nil.
    context "propagates an empty rect to its whole subtree" do
      catalog.each_key do |klass|
        it klass.name do
          component = instance_exec(&catalog[klass])
          paint(component)
          descendants = []
          component.walk_tree { descendants << _1 unless _1.equal?(component) }
          skip "no children to propagate to" if descendants.empty?
          skip "places no children from its own size: an Absolute's are fixed" unless places_children?(component)

          place(component, Rect.new(contract_rect.left, contract_rect.top, 0, 0))
          stale = descendants.reject { _1.rect.empty? }
          assert_empty stale.map { "#{_1.class}#{_1.rect.inspect}" },
                       "#{klass} left descendants at their old rects"
        end
      end
    end

    # AGENTS.md, Layout: `relayout` derives every rect from current state, so
    # running it twice over unchanged state assigns the same rects. Nothing
    # enforces it, and the failure is silent: the pass runs to a fixpoint
    # (`D_deferred_layout`), so a container that *accumulates* — adding an
    # offset rather than computing one — either drifts a cell per event or, once
    # its own marks feed the drain, hangs the UI thread outright.
    context "relayout is idempotent" do
      catalog.each_key do |klass|
        it klass.name do
          component = instance_exec(&catalog[klass])
          paint(component)
          before = descendant_rects(component)
          skip "no children to place" if before.empty?

          component.__send__(:perform_relayout)
          Screen.instance.flush_layout
          assert_equal before, descendant_rects(component),
                       "#{klass} moved its children on a second pass over the same state"
        end
      end
    end

    # AGENTS.md, The tree: hiding is `visible = false` — as if detached,
    # but still in the tree. Three obligations, all framework-wide, none
    # enforced at runtime, and each failing silently in its own way: a widget
    # that paints anyway overwrites a *neighbour*; one that keeps its tab stop
    # takes keystrokes the user cannot see; and one that does not come back
    # identical has quietly lost state a detach would legitimately have cost it.
    #
    # An {Component::Overlay} refuses the flag outright (it is closed instead),
    # so the family is exempt by construction rather than by omission.
    context "hides and comes back" do
      catalog.each_key do |klass|
        it klass.name do
          component = instance_exec(&catalog[klass])
          skip "an overlay is dismissed, not hidden" if component.is_a?(Component::Overlay)

          buffer = paint(component)
          # Drain the cascade too: the default #repaint only invalidates its
          # children, so without this the "before" picture is the container's
          # own cells over a sentinel field, and the comparison after showing
          # would be against a fully painted tree.
          Screen.instance.repaint
          # And blank the sentinel {#paint} laid down for the stray sweep, then
          # paint the subtree again onto the blank: whatever shows through where
          # the component paints nothing is not part of its picture, and the
          # round trip below has the parent legitimately clear it.
          buffer.clear(StyledString::Style::DEFAULT)
          buffer.fill(Rect.new(0, 0, buffer.width, buffer.height), StyledString::Style::DEFAULT)
          component.walk_tree { Screen.instance.invalidate(_1) }
          Screen.instance.repaint
          before = buffer.region_text(component.absolute_rect)
          stops_before = tab_stops(component)

          component.visible = false
          # Let the hide settle first — the parent legitimately repaints the
          # cells its child just vacated. Then the sentinel, and a *further*
          # frame, which a hidden component must leave untouched.
          Screen.instance.repaint
          fill_sentinel(buffer)
          Screen.instance.repaint
          painted = cells_outside(buffer, Rect.new(0, 0, 0, 0))
          assert_empty painted.first(5), "#{klass} painted while hidden"
          assert_empty tab_stops(component), "#{klass} kept a tab stop while hidden"

          component.visible = true
          Screen.instance.repaint
          assert_equal before, buffer.region_text(component.absolute_rect),
                       "#{klass} did not come back as it was"
          assert_equal stops_before, tab_stops(component), "#{klass} did not get its tab stops back"
        end
      end
    end

    # @param component [Component]
    # @return [Array<Component>] the tab stops a user can actually reach in this
    #   subtree — the walk Screen#cycle_focus takes.
    def tab_stops(component)
      stops = []
      component.walk_shown_tree { stops << _1 if _1.tab_stop? }
      stops
    end
  end
end
