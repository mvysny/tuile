# frozen_string_literal: true

module Tuile
  # Finds a component in the tree, so a spec can drive the UI it built four
  # layers down:
  #
  #   Testing.get(id: :save).handle_key?(Keys::ENTER)
  #   Testing.get(Component::TextField, id: :name).value = "Zaphod"
  #   Testing.find(Component::Checkbox, in: pane, count: 3)
  #
  # {.get} demands exactly one match and raises with a {.dump} of the tree it
  # searched; {.find} returns every match and takes an optional `count:`. Both
  # search {Screen}'s whole tree by default — popups included, since they live
  # under the same {ScreenPane} as the content — or the subtree given as `in:`.
  #
  # **The handles are structural — a class, an {Component#id}, a subtree — never
  # what a component *says*.** There is no `caption:` filter: chrome text is UI
  # copy, and a lookup keyed to it makes a rewording break a spec that tests
  # nothing about the wording. Where a spec does want it, the block says so
  # per-class and needs nothing from the framework:
  #
  #   Testing.get(Component::Button) { _1.caption.to_s == "Save" }
  #
  # See `D_component_lookup`.
  #
  # **Call these qualified**, as above: `find` and `get` collide with names a
  # spec suite is likely to have already (Capybara's `find`), so there is no
  # `Component#get` and mixing this module in is not recommended. Tuile's own
  # specs sit inside `module Tuile` and so need no include.
  #
  # **A hidden component is never found**: these simulate a user, and a spec
  # that drove a hidden {Component::Button} would pass against a form nobody
  # can operate. Both walk {Component#walk_shown_tree}; a failed lookup says how
  # many hidden components *would* have matched, and {.dump} shows them.
  #
  #   Testing.find(Component::TextField, count: 0)   # the user can't reach it
  #   refute field.visible?                          # it is hidden
  #
  # There is deliberately no `visible:` filter handing one back to drive
  # (`D_visibility`).
  #
  # == Setup
  #
  # A spec dispatches no event, so nothing lays out what a mutation left
  # pending: call {Component#flush_layout} before reading a rect — it settles
  # the whole tree, from any component in it. {.place} sizes a component the
  # way its parent would (`rect=` raises outside the parent's `relayout`) and
  # settles on its own:
  #
  #   Testing.place(field, Rect.new(0, 0, 20, 1))   # already settled
  #   field.visible = false
  #   field.flush_layout                            # before reading any rect
  #
  # The terminal is 160×50; pick another size with `Screen.fake(width:, height:)`,
  # or resize mid-example as the terminal would report it:
  #
  #   Screen.instance.resize_terminal(80, 24)      # FakeScreen#resize_terminal
  #
  # == Gestures
  #
  # Drive what you found as a *user* would: {.click} routes a real press and
  # {.set_value} refuses a field the keyboard cannot reach, where a bare
  # `handle_key?` or `value=` on a handle asserts neither.
  # {Tuile::Testing::Gestures} gives them receiver syntax:
  #
  #   using Tuile::Testing::Gestures
  #
  #   Testing.get(Component::TextField, id: :name)._value = "Zaphod"
  #   Testing.get(Component::Button, id: :save)._click
  #
  # For *what a component shows*, assert on {Screen#buffer} instead — this
  # locates and drives, it does not replace that channel. See book ch8 for the
  # worked usage, and `design/decisions.md` `D_component_lookup` / `D_test_gestures`
  # for the design.
  module Testing
    # Raised by every lookup and every gesture that does not hold: the match
    # count is not the one asked for, or a gesture was handed a component no
    # user could have operated.
    #
    # **Not a {Tuile::Error}**, which is production's. It descends from
    # `Exception` rather than `StandardError` for the reason
    # `Minitest::Assertion` does: a stray `rescue` must not swallow a failed
    # assertion. Tuile defines its own because the gem depends on no test
    # framework.
    class AssertionError < Exception; end # rubocop:disable Lint/InheritException

    class << self
      # Every component in the searched tree matching the spec, in pre-order.
      #
      #   find(Component::Button)                     # every button on screen
      #   find(Component::HasBadInput, in: form)      # a mixin works too
      #   find(Component::Label) { _1.text.to_s.start_with?("Total") }
      #   find(Component::Popup, count: 1..)          # assert at least one
      #
      # @param klass [Module] matched with `is_a?`, so a mixin
      #   ({Component::HasValue}) finds every field that includes it.
      # @param in [Component, nil] root of the subtree to search, itself
      #   included. Defaults to `Screen.instance.pane` — the whole UI.
      # @param id [Symbol, nil] matched against {Component#id}.
      # @param count [Integer, Range, nil] how many matches are expected; any
      #   number when nil.
      # @yield [component] optional extra predicate; a component matches only
      #   when the block returns truthy. This is where a text test goes — see
      #   the module doc for why there is no `caption:` term.
      # @yieldparam component [Component]
      # @yieldreturn [Boolean]
      # @raise [AssertionError] if `count` is given and the match count differs.
      # @return [Array<Component>]
      def find(klass = Component, in: nil, id: nil, count: nil, &predicate)
        # `in` is a Ruby keyword, so the local it binds is unreachable by name.
        scope = binding.local_variable_get(:in) || Screen.instance.pane
        spec = ->(c) { matches_spec?(c, klass, id, predicate) }
        matches = []
        scope.walk_shown_tree { |c| matches << c if spec.call(c) }
        return matches if count.nil? || spec_match?(count, matches.size)

        raise AssertionError, failure(klass, id, predicate, count, matches, scope, spec)
      end

      # The one component matching the spec — {.find} with `count: 1`, so it
      # raises rather than returning nil, and raises on an ambiguous spec too.
      #
      #   get(Component::ComboBox, in: sampler.demo_window)
      #
      # @param klass [Module] see {.find}.
      # @param in [Component, nil] see {.find}.
      # @param id [Symbol, nil] see {.find}.
      # @yield [component] see {.find}.
      # @yieldparam component [Component]
      # @yieldreturn [Boolean]
      # @raise [AssertionError] unless exactly one component matches.
      # @return [Component]
      def get(klass = Component, in: nil, id: nil, &predicate)
        scope = binding.local_variable_get(:in)
        find(klass, in: scope, id:, count: 1, &predicate).first
      end

      # The searched tree, one component per row, indented by depth and with
      # the `Tuile::` namespaces stripped so a fifty-row dump stays readable
      # (an app's own component classes keep their full name):
      #
      #     #<ScreenPane rect=(0,0 160x50)>
      #       #<Window rect=(0,0 40x10) caption="Settings">
      #         #<Layout::Vertical rect=(1,1 38x8)>
      #   →       #<Button id=:save rect=(1,1 38x1) caption="Save">
      #
      # @param scope [Component] root of the tree to dump.
      # @param marked [Array<Component>] components to flag with a leading
      #   arrow — the matches, when a lookup found the wrong number of them.
      # @param excluded [Array<Component>] components to flag with `⊘` — ones
      #   that matched the spec but were skipped for being hidden.
      # @return [String]
      def dump(scope, marked = [], excluded = [])
        settle_layout
        base = scope.depth
        rows = []
        # walk_tree, not walk_shown_tree: a reader looks here to find out where
        # their component went, so the ones the search skipped are the point.
        scope.walk_tree do |c|
          mark = if marked.any? { _1.equal?(c) } then "→"
                 elsif excluded.any? { _1.equal?(c) } then "⊘"
                 else " "
                 end
          row = brief(c)
          rows << "#{mark} #{"  " * (c.depth - base)}#{row}"
        end
        rows.join("\n")
      end

      # Clicks `component` as the terminal would: a press and a release at the
      # top-left cell of its {Component#absolute_extent_rect}, posted through
      # {Screen#handle_mouse}, so it focuses and dismisses popups exactly as a
      # real click does.
      #
      #   Testing.click(Testing.get(Component::Button, id: :save))
      #
      # It does **not** raise when the press lands and nobody claims it: a user
      # really can click a {Component::Label} and have nothing happen, so this
      # asserts the click was possible, not that it achieved something.
      # @param component [Component]
      # @param button [Symbol] `:left`, `:middle` or `:right`.
      # @raise [AssertionError] unless a press at that cell reaches `component`
      #   — it is unattached, hidden, collapsed to no cells, or covered.
      # @return [void]
      def click(component, button: :left)
        point = gesture_point(component)
        path = component_path_at(point)
        unless path.include?(component)
          reached = path.empty? ? "nothing — a modal popup is open" : brief(path.last)
          raise AssertionError, "#{brief(component)} is not clickable at #{point.x},#{point.y}: " \
                                "a press there reaches #{reached}\n" \
                                "searched:\n#{dump(Screen.instance.pane, [component])}"
        end

        Screen.instance.handle_mouse(Mouse::DownEvent.new(button, point.x, point.y))
        Screen.instance.handle_mouse(Mouse::UpEvent.new(point.x, point.y))
      end

      # Sets a field's value as a user who could reach it would.
      #
      #   Testing.set_value(Testing.get(Component::IntegerField, id: :age), 25)
      #
      # **Moves no focus** — no keystroke is involved — and assigns through
      # `value=`, so it is the value-level shortcut rather than a simulation of
      # typing: the editor's `insert_text` and its input filters never run.
      # @param component [Component]
      # @param value [Object] whatever the field's {Component::HasValue#value=} takes.
      # @raise [AssertionError] unless `component` is a {Component::HasValue}
      #   the keyboard can reach: shown with every ancestor shown, and inside
      #   {ScreenPane#key_scope}, so a field behind a modal popup refuses.
      # @return [void]
      def set_value(component, value)
        unless component.is_a?(Component::HasValue)
          raise AssertionError, "#{brief(component)} is not a field: set_value needs a Component::HasValue"
        end
        unless component.focusable?
          raise AssertionError, "#{brief(component)} is not focusable, so a user could never edit it"
        end

        scope = Screen.instance.pane.key_scope
        unless reachable?(component, scope)
          where = scope.nil? ? "the pane has no content" : "the key scope is #{brief(scope)}"
          raise AssertionError, "#{brief(component)} is hidden or out of reach: #{where}\n" \
                                "searched:\n#{dump(Screen.instance.pane, [component])}"
        end

        component.value = value
      end

      # Puts `component` at `rect` through whatever places it, since
      # {Component#rect=} raises outside the parent's `relayout`:
      #
      #   Testing.place(label, Rect.new(0, 0, 10, 1))      # a parentless root
      #   Testing.place(field, Rect.new(2, 1, 20, 1))      # moves it in its Layout::Absolute
      #   Testing.place(popup, Rect.new(5, 5, 30, 10))     # an open overlay: At[rect]
      #
      # A parentless root is sized in a throwaway {Component::Layout::Absolute}
      # and released again, so it stays unattached. A child of the pane that is
      # not an overlay is moved into a fresh holder that replaces the content —
      # straight on the pane it would be handed the whole screen on the next pass.
      # The pane itself is sized by {FakeScreen#resize_terminal}.
      # @param component [Component]
      # @param rect [Rect] in the parent's coordinates (the screen's, for an
      #   overlay).
      # @raise [ArgumentError] if any other container places `component` —
      #   move it by its constraint there.
      # @return [Component] `component`, settled.
      def place(component, rect)
        parent = component.parent
        case parent
        when nil
          holder = Component::Layout::Absolute.new
          holder.add(component, rect)
          holder.flush_layout
          holder.remove(component)
        when Component::Layout::Absolute
          parent.constrain(component, rect)
        when ScreenPane
          if component.is_a?(Component::Overlay)
            component.placement = Component::Overlay::At[rect]
          else
            holder = Component::Layout::Absolute.new
            Screen.instance.content = holder
            holder.add(component, rect)
          end
        else
          raise ArgumentError, "place: #{parent} places #{component} itself; constrain it there"
        end
        component.tap(&:flush_layout)
      end

      # The shown components under `point`, outermost first — the descent
      # {Mouse::Router} makes when the terminal reports a press there.
      #
      # A deliberate copy of the router's private walk, kept honest by
      # `testing_spec`'s pin against where a press is really delivered. When
      # that pin gets hard to keep green the two have diverged for a reason:
      # move the walk onto {Mouse::Router} and delete this.
      # @param point [Point]
      # @return [Array<Component>]
      def component_path_at(point)
        settle_layout
        path = []
        component = Screen.instance.pane.mouse_root_at(point)
        while component&.visible? && component.rect.contains?(point)
          # Rebase into the component's own coordinates as the router does:
          # a rect is parent-relative (`D_relative_rect`).
          point = Point.new(point.x - component.rect.left, point.y - component.rect.top)
          path << component
          component = component.children.find { _1.visible? && _1.rect.contains?(point) }
        end
        path
      end

      private

      # The cell a pointer gesture aims at: the top-left of what the component
      # actually paints.
      #
      # The three refusals are ordered because a layout gives a hidden child no
      # row, so a *hidden* component reaches the geometry check with an empty
      # rect and would be reported as collapsed if that ran first.
      # @param component [Component] the target of a pointer gesture.
      # @raise [AssertionError] if no cell of it could be clicked.
      # @return [Point]
      def gesture_point(component)
        settle_layout
        raise AssertionError, "#{brief(component)} is not attached to the screen" unless component.attached?

        unless reachable?(component, Screen.instance.pane)
          raise AssertionError, "#{brief(component)} is hidden, or sits under a hidden ancestor"
        end

        rect = component.absolute_extent_rect
        if rect.empty?
          raise AssertionError, "#{brief(component)} has no cell to click: the tree was never laid " \
                                "out (repaint the screen first), or it is deliberately collapsed"
        end

        Point.new(rect.left, rect.top)
      end

      # Brings child rects up to date before anything here reads one — these
      # helpers run straight from spec code, with no event dispatched to settle
      # the layout the way the loop's would. A no-op with nothing pending.
      # @return [void]
      def settle_layout
        Screen.instance.flush_layout if Screen.instance?
      end

      # Whether `component` is shown, ancestors included, *and* inside `scope`.
      # One walk answers both: `walk_shown_tree` skips a hidden subtree whole.
      # @param component [Component]
      # @param scope [Component, nil] see {ScreenPane#key_scope}.
      # @return [Boolean]
      def reachable?(component, scope)
        return false if scope.nil?

        scope.walk_shown_tree { |c| return true if c.equal?(component) }
        false
      end

      # @param component [Component]
      # @return [String] its `inspect` with the `Tuile::` namespaces stripped,
      #   as {.dump} prints it.
      def brief(component)
        component.inspect.sub("#<Tuile::Component::", "#<").sub("#<Tuile::", "#<")
      end

      # @param component [Component]
      # @param klass [Module] see {.find}.
      # @param id [Symbol, nil] see {.find}.
      # @param predicate [Proc, nil] see {.find}.
      # @return [Boolean] whether the component satisfies every given term.
      #   Visibility is the *walk's* business, deliberately not tested here, so
      #   {.failure} can re-run this over the components the walk skipped.
      def matches_spec?(component, klass, id, predicate)
        return false unless component.is_a?(klass)
        return false unless id.nil? || component.id == id

        predicate.nil? || predicate.call(component)
      end

      # Whether `actual` satisfies a `count:` spec, which may be an exact value
      # or a pattern — `===` is the feature, not an accident: an Integer matches
      # exactly and a Range as a bound.
      # @param spec [Object] the expected value or pattern.
      # @param actual [Object]
      # @return [Boolean]
      def spec_match?(spec, actual) = spec === actual # rubocop:disable Style/CaseEquality

      # @param klass [Module] the class or mixin that was asked for.
      # @param id [Symbol, nil] the id spec, if any.
      # @param predicate [Proc, nil] the block spec, if any.
      # @param count [Integer, Range] the count that was not met.
      # @param matches [Array<Component>] what the search did find.
      # @param scope [Component] the root that was searched.
      # @param spec [Proc] the same term test the search ran, re-run over the
      #   components the walk skipped.
      # @return [String]
      def failure(klass, id, predicate, count, matches, scope, spec)
        wanted = [(klass.name || klass.to_s).sub("Tuile::", "")]
        wanted << "id=#{id.inspect}" unless id.nil?
        wanted << "matching the block" unless predicate.nil?
        excluded = hidden_matches(scope, spec)
        "expected #{count} #{wanted.join(" ")}, found #{matches.size}#{excluded_note(excluded)}\n" \
          "searched:\n#{dump(scope, matches, excluded)}"
      end

      # The components that satisfy the spec but were skipped for being hidden
      # — the answer to the "but it *is* there" a failed lookup provokes.
      # @param scope [Component] the root that was searched.
      # @param spec [Proc] the term test.
      # @return [Array<Component>]
      def hidden_matches(scope, spec)
        shown = Set.new
        scope.walk_shown_tree { shown << _1 }
        hidden = []
        scope.walk_tree { |c| hidden << c if !shown.include?(c) && spec.call(c) }
        hidden
      end

      # @param excluded [Array<Component>] see {.hidden_matches}.
      # @return [String] the clause naming them, or "" when there were none.
      def excluded_note(excluded)
        return "" if excluded.empty?

        " (#{excluded.size} hidden #{excluded.size == 1 ? "match" : "matches"} excluded)"
      end
    end
  end
end
