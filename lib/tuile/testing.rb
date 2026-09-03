# frozen_string_literal: true

module Tuile
  # Finds one component in a tree, for a spec that wants to drive the UI rather
  # than read the painted buffer:
  #
  #   Testing.get(Component::Button, caption: "Save").handle_key(Keys::ENTER)
  #   Testing.get(id: :name).value = "Zaphod"
  #   Testing.find(Component::Checkbox, in: pane, count: 3)
  #
  # {.get} demands exactly one match; {.find} returns every match and takes an
  # optional `count:`. Both search {Screen}'s whole tree by default — popups
  # included, since they live under the same {ScreenPane} as the content — or
  # the subtree given as `in:`.
  #
  # Call these qualified, as above. There is deliberately no `Component#get`
  # and no recommended `config.include Tuile::Testing`: `find` and `get` are
  # the two most collision-prone names in a spec suite (an app driving Capybara
  # already has a `find`), and scope is a parameter of the search rather than a
  # property of a component. Tuile's own specs sit inside `module Tuile`, so
  # `Testing.get` resolves there with nothing to include.
  #
  # This is additive: it makes *driving* a tree terser, and does not replace
  # the buffer as the assertion channel (`DECISIONS.md` `D_list_items`). A spec
  # asserting what a component *shows* still asserts `Screen#buffer`, and one
  # asserting nothing is open still says `assert_empty Screen.instance.popups`
  # — a direct assertion on the list beats a lookup that finds nothing.
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
        matches = []
        scope.on_tree do |c|
          next unless c.is_a?(klass)
          next unless id.nil? || c.id == id
          next unless caption.nil? || (c.is_a?(Component::HasCaption) && spec_match?(caption, c.caption.to_s))
          next unless predicate.nil? || predicate.call(c)

          matches << c
        end
        return matches if count.nil? || spec_match?(count, matches.size)

        raise LookupError, failure(klass, id, caption, predicate, count, matches, scope)
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
      # @return [String]
      def dump(scope, marked = [])
        base = scope.depth
        rows = []
        scope.on_tree do |c|
          hit = marked.any? { _1.equal?(c) }
          row = c.inspect.sub("#<Tuile::Component::", "#<").sub("#<Tuile::", "#<")
          rows << "#{hit ? "→" : " "} #{"  " * (c.depth - base)}#{row}"
        end
        rows.join("\n")
      end

      private

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
      # @return [String]
      def failure(klass, id, caption, predicate, count, matches, scope)
        spec = [(klass.name || klass.to_s).sub("Tuile::", "")]
        spec << "id=#{id.inspect}" unless id.nil?
        spec << "caption=#{caption.inspect}" unless caption.nil?
        spec << "matching the block" unless predicate.nil?
        "expected #{count} #{spec.join(" ")}, found #{matches.size}\n" \
          "searched:\n#{dump(scope, matches)}"
      end
    end
  end
end
