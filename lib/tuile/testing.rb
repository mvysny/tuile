# frozen_string_literal: true

module Tuile
  # Finds a component in the tree, so a spec can drive the UI it built four
  # layers down:
  #
  #   Testing.get(Component::Button, caption: "Save").handle_key(Keys::ENTER)
  #   Testing.get(id: :name).value = "Zaphod"
  #   Testing.find(Component::Checkbox, in: pane, count: 3)
  #
  # {.get} demands exactly one match and raises with a {.dump} of the tree it
  # searched; {.find} returns every match and takes an optional `count:`. Both
  # search {Screen}'s whole tree by default — popups included, since they live
  # under the same {ScreenPane} as the content — or the subtree given as `in:`.
  #
  # **Call these qualified**, as above: `find` and `get` collide with names a
  # spec suite is likely to have already (Capybara's `find`), so there is no
  # `Component#get` and mixing this module in is not recommended. Tuile's own
  # specs sit inside `module Tuile` and so need no include.
  #
  # **A hidden component is never found.** These simulate a user, and a user
  # cannot click what is not on the screen — a locator that reached a hidden
  # {Component::Button} would let a spec pass against a form nobody can operate.
  # So both walk {Component#on_shown_tree}, skipping a hidden subtree whole; a
  # failure says how many hidden components *would* have matched, and {.dump}
  # shows them (`D_visibility`). To assert that something is hidden, hold the
  # component and check `refute field.visible?`; to assert the user cannot reach
  # it, `find(…, count: 0)`. There is deliberately no `visible:` filter that
  # would hand back a hidden component to drive.
  #
  # For *what a component shows*, assert on {Screen#buffer} instead — this
  # locates and drives, it does not replace that channel. See book ch8 for the
  # worked usage and `DECISIONS.md` `D_component_lookup` for the design.
  module Testing
    # Raised when the match count is not the one asked for. A {Tuile::Error},
    # so an app rescuing that still catches it.
    class LookupError < Error; end

    class << self
      # Every component in the searched tree matching the spec, in pre-order.
      #
      #   find(Component::Button)                     # every button on screen
      #   find(Component::HasBadInput, in: form)      # a mixin works too
      #   find(Component::Label, caption: /^Total/)   # Regexp: partial match
      #   find(Component::Popup, count: 1..)          # assert at least one
      #
      # @param klass [Module] matched with `is_a?`, so a mixin
      #   ({Component::HasValue}) finds every field that includes it.
      # @param in [Component, nil] root of the subtree to search, itself
      #   included. Defaults to `Screen.instance.pane` — the whole UI.
      # @param id [Symbol, nil] matched against {Component#id}.
      # @param caption [String, Regexp, nil] matched with `===` against
      #   {Component::HasCaption#caption}`.to_s`, so a String is exact and a
      #   Regexp is a partial match. Never matches a component without a
      #   caption.
      # @param count [Integer, Range, nil] how many matches are expected; any
      #   number when nil.
      # @yield [component] optional extra predicate; a component matches only
      #   when the block returns truthy.
      # @yieldparam component [Component]
      # @yieldreturn [Boolean]
      # @raise [LookupError] if `count` is given and the match count differs.
      # @return [Array<Component>]
      def find(klass = Component, in: nil, id: nil, caption: nil, count: nil, &predicate)
        # `in` is a Ruby keyword, so the local it binds is unreachable by name.
        scope = binding.local_variable_get(:in) || Screen.instance.pane
        spec = ->(c) { matches_spec?(c, klass, id, caption, predicate) }
        matches = []
        scope.on_shown_tree { |c| matches << c if spec.call(c) }
        return matches if count.nil? || spec_match?(count, matches.size)

        raise LookupError, failure(klass, id, caption, predicate, count, matches, scope, spec)
      end

      # The one component matching the spec — {.find} with `count: 1`, so it
      # raises rather than returning nil, and raises on an ambiguous spec too.
      #
      #   get(Component::ComboBox, in: sampler.demo_window)
      #
      # @param klass [Module] see {.find}.
      # @param in [Component, nil] see {.find}.
      # @param id [Symbol, nil] see {.find}.
      # @param caption [String, Regexp, nil] see {.find}.
      # @yield [component] see {.find}.
      # @yieldparam component [Component]
      # @yieldreturn [Boolean]
      # @raise [LookupError] unless exactly one component matches.
      # @return [Component]
      def get(klass = Component, in: nil, id: nil, caption: nil, &predicate)
        scope = binding.local_variable_get(:in)
        find(klass, in: scope, id:, caption:, count: 1, &predicate).first
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
        # The *whole* tree, hidden subtrees included: this is where a reader
        # looks to find out where their component went, so leaving out the ones
        # the search skipped would hide exactly the answer. Each such component
        # says `hidden` in its own inspect.
        scope.on_tree do |c|
          mark = if marked.any? { _1.equal?(c) } then "→"
                 elsif excluded.any? { _1.equal?(c) } then "⊘"
                 else " "
                 end
          row = c.inspect.sub("#<Tuile::Component::", "#<").sub("#<Tuile::", "#<")
          rows << "#{mark} #{"  " * (c.depth - base)}#{row}"
        end
        rows.join("\n")
      end

      private

      # @param component [Component]
      # @param klass [Module] see {.find}.
      # @param id [Symbol, nil] see {.find}.
      # @param caption [String, Regexp, nil] see {.find}.
      # @param predicate [Proc, nil] see {.find}.
      # @return [Boolean] whether the component satisfies every given term.
      #   Says nothing about visibility — that is the walk's business, and
      #   keeping it out of here is what lets {.failure} re-run the same spec
      #   over the hidden components to count them.
      def matches_spec?(component, klass, id, caption, predicate)
        return false unless component.is_a?(klass)
        return false unless id.nil? || component.id == id
        if !caption.nil? &&
           !(component.is_a?(Component::HasCaption) && spec_match?(caption, component.caption.to_s))
          return false
        end

        predicate.nil? || predicate.call(component)
      end

      # Whether `actual` satisfies a spec value, which for both `caption:` and
      # `count:` may be either an exact value or a pattern — `===` is the
      # feature, not an accident: a String caption matches exactly and a Regexp
      # partially, an Integer count exactly and a Range as a bound.
      # @param spec [Object] the expected value or pattern.
      # @param actual [Object]
      # @return [Boolean]
      def spec_match?(spec, actual) = spec === actual # rubocop:disable Style/CaseEquality

      # @param klass [Module] the class or mixin that was asked for.
      # @param id [Symbol, nil] the id spec, if any.
      # @param caption [String, Regexp, nil] the caption spec, if any.
      # @param predicate [Proc, nil] the block spec, if any.
      # @param count [Integer, Range] the count that was not met.
      # @param matches [Array<Component>] what the search did find.
      # @param scope [Component] the root that was searched.
      # @param spec [Proc] the same term test the search ran, re-run over the
      #   components the walk skipped.
      # @return [String]
      def failure(klass, id, caption, predicate, count, matches, scope, spec)
        wanted = [(klass.name || klass.to_s).sub("Tuile::", "")]
        wanted << "id=#{id.inspect}" unless id.nil?
        wanted << "caption=#{caption.inspect}" unless caption.nil?
        wanted << "matching the block" unless predicate.nil?
        excluded = hidden_matches(scope, spec)
        "expected #{count} #{wanted.join(" ")}, found #{matches.size}#{excluded_note(excluded)}\n" \
          "searched:\n#{dump(scope, matches, excluded)}"
      end

      # The components that satisfy the spec but were skipped for being hidden
      # — the whole reason the failure message is worth reading, since "it *is*
      # there" is the first thing the reader will think.
      # @param scope [Component] the root that was searched.
      # @param spec [Proc] the term test.
      # @return [Array<Component>]
      def hidden_matches(scope, spec)
        shown = Set.new
        scope.on_shown_tree { shown << _1 }
        hidden = []
        scope.on_tree { |c| hidden << c if !shown.include?(c) && spec.call(c) }
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
