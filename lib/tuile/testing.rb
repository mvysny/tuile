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
  # == Gestures
  #
  # Having found a component, drive it as a *user* would — {.click} routes a
  # real press through {Mouse::Router}, and {.set_value} refuses a field the
  # keyboard cannot reach. Both raise rather than doing nothing quietly, which
  # is the whole point: calling `handle_key?` or `value=` on a handle asserts
  # nothing about whether anyone could have done that.
  #
  # {Tuile::Testing::Gestures} gives them receiver syntax, per file or per
  # `describe` block:
  #
  #   using Tuile::Testing::Gestures
  #
  #   Testing.get(Component::TextField, id: :name)._value = "Zaphod"
  #   Testing.get(Component::Button, id: :save)._click
  #
  # The leading underscore is the house mark for "this is the testing API, not
  # the component's own" — see that module.
  #
  # For *what a component shows*, assert on {Screen#buffer} instead — this
  # locates and drives, it does not replace that channel. See book ch8 for the
  # worked usage and `design/decisions.md` `D_component_lookup` for the design.
  module Testing
    # Raised by every lookup and every gesture that does not hold: the match
    # count is not the one asked for, or the component a gesture was handed is
    # not one a user could have operated.
    #
    # **Not a {Tuile::Error}** — that is production's, and a failed gesture is a
    # test assertion. It descends from `Exception` rather than `StandardError`
    # for the reason `Minitest::Assertion` does: nobody should be capturing one,
    # and a stray `rescue` must not swallow it. Tuile raises its own rather than
    # minitest's because the gem depends on no test framework.
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

      # Clicks `component` the way the terminal would: a press and a release at
      # the top-left cell of its {Component#extent_rect}, posted through
      # {Screen#handle_mouse}, so it focuses, dismisses popups, bubbles and
      # grabs exactly as a real click does.
      #
      #   Testing.click(Testing.get(Component::Button, id: :save))
      #
      # Raises unless a press at that cell actually *reaches* the component: a
      # modal popup is open, another popup covers it, an ancestor is hidden.
      # It does **not** raise when the press reaches it and nobody claims it —
      # a user really can click a {Component::Label} and have nothing happen,
      # and this asserts that the click was possible, not that it did something.
      # @param component [Component]
      # @param button [Symbol] `:left`, `:middle` or `:right`.
      # @raise [AssertionError] if the component has no geometry, or the press
      #   would not reach it.
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
      # Raises unless `component` is a {Component::HasValue} the keyboard can
      # reach — shown (ancestors included) and inside the current key scope, so
      # a field behind an open modal popup refuses. **Focus is deliberately not
      # moved**: no keystroke is involved, so there is nothing to deliver.
      #
      # This is the value-level shortcut, not a simulation of typing: it
      # assigns through `value=` and so does **not** exercise the editor's
      # `insert_text` or its input filters.
      # @param component [Component]
      # @param value [Object] whatever the field's {Component::HasValue#value=} takes.
      # @raise [AssertionError] if it is not a field, or not reachable.
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

      # The shown components under `point`, outermost first — the descent
      # {Mouse::Router} makes when the terminal reports a press there: the
      # topmost popup containing the point, else the content unless a modal
      # popup is open ({ScreenPane#mouse_root_at}), then down through the
      # children whose {Component#rect} contains it.
      #
      # Deliberately a *copy* of the router's own private walk rather than a new
      # public seam on {Screen}: this is test-only, so a drift shows up as a
      # spec that lies rather than a shipped bug, and `testing_spec` pins the
      # two together over a tree with popups open. If that pin ever becomes hard
      # to keep green the walk has diverged for a real reason — move it onto
      # {Mouse::Router} then, and delete this.
      # @param point [Point]
      # @return [Array<Component>]
      def component_path_at(point)
        path = []
        component = Screen.instance.pane.mouse_root_at(point)
        while component&.visible? && component.rect.contains?(point)
          path << component
          component = component.children.find { _1.visible? && _1.rect.contains?(point) }
        end
        path
      end

      private

      # The cell a pointer gesture aims at: the top-left of what the component
      # actually paints.
      #
      # The three refusals are ordered, and the order is the point — a layout
      # gives a hidden child no row ({Component#handle_child_visibility_changed}),
      # so a hidden component reaches the geometry check with an empty rect and
      # would be reported as *collapsed* if that ran first.
      # @param component [Component] the target of a pointer gesture.
      # @raise [AssertionError] if no cell of it could be clicked.
      # @return [Point]
      def gesture_point(component)
        raise AssertionError, "#{brief(component)} is not attached to the screen" unless component.attached?

        unless reachable?(component, Screen.instance.pane)
          raise AssertionError, "#{brief(component)} is hidden, or sits under a hidden ancestor"
        end

        rect = component.extent_rect
        if rect.empty?
          raise AssertionError, "#{brief(component)} has no cell to click: the tree was never laid " \
                                "out (repaint the screen first), or it is deliberately collapsed"
        end

        Point.new(rect.left, rect.top)
      end

      # Whether the keyboard can reach `component` at all: shown with every
      # ancestor shown, *and* inside the key scope. One walk answers both,
      # because `walk_shown_tree` skips a hidden subtree whole — the same walk
      # {.find} runs and {Screen#cycle_focus} collects its tab stops from.
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
