# frozen_string_literal: true

module Tuile
  class Component
    # A layout doesn't paint anything by itself: its job is to position child
    # components. Three ways to use one, all top-down (see book ch3):
    #
    # - Subclass {Layout} and compute every child's rectangle yourself in a
    #   {Component#relayout} override. Total control, and the base for anything
    #   unusual:
    #
    #     class SplitPane < Component::Layout
    #       def initialize
    #         super
    #         add(@sidebar = Component::List.new)
    #         add(@main = Component::Window.new("Main"))
    #       end
    #
    #       protected
    #
    #       def relayout
    #         left = width * 4 / 10
    #         @sidebar.rect = Rect.new(0, 0, left, height)
    #         @main.rect = Rect.new(left, 0, width - left, height)
    #       end
    #     end
    #
    #   The framework runs it after a resize, an `add` or `remove`, and a
    #   child's {Component#visible=}.
    # - {Absolute} — you give each child a fixed {Rect} and the layout assigns
    #   exactly that.
    # - {Box} / {Vertical} / {Horizontal} — you declare each child's extent as
    #   a {Fixed}, {Percent} or {Expand} constraint — a {Percent} optionally
    #   bounded with {Percent#clamp} — and the layout does the arithmetic.
    #
    # Children that fully tile the layout's rect repaint themselves and
    # cover everything; children that leave gaps (e.g. a form with widgets
    # of varying widths) trigger {Component#repaint}'s default behavior —
    # the background is cleared and children are re-invalidated so they
    # paint over a clean surface.
    class Layout < Component
      # What {Fixed}, {Percent}, {Expand} and {Clamp} have in common: each is a
      # value a {Box} resolves against the space it has. The set is closed —
      # {Box#add} accepts these four and nothing else, so an app never
      # implements the protocol.
      module Constraint
        # @api private
        # @param available [Integer] the extent a {Box} divides.
        # @return [Integer, nil] cells wanted, before the box clamps to what is
        #   left; `nil` for an {Expand}, which takes a share of the residue instead.
        def resolve(available) = raise(NotImplementedError, "#{self.class} must implement resolve")
      end

      # How much space a child gets along one axis of a {Box}: exactly {#cells},
      # clamped to whatever is still unassigned.
      #
      #   add(prompt, Fixed[4])                    # 4 rows in a Vertical
      #   add(field, Fixed[1], cross: Fixed[30])   # 1 row, 30 columns wide
      #
      # `Fixed[0]` *collapses* the child: it and its whole subtree get an empty
      # rect and paint nothing. That is not the same as hiding it — an empty
      # rect is a paint convention and gates nothing else, so the subtree keeps
      # its tab stops and still takes keys. **To hide a child, set
      # {Component#visible=} false**; it then costs no {Box#spacing} gap either,
      # where a collapsed child still does. The difference is exactly that: a
      # collapsed child is still a member of the sequence, a hidden one is not
      # (`D_visibility`).
      #
      # @!attribute [r] cells
      #   @return [Integer] cell count along the axis.
      class Fixed < Data.define(:cells)
        include Constraint

        # @param cells [Integer] cell count along the axis; `>= 0`.
        # @raise [ArgumentError] unless `cells` is a non-negative Integer.
        def initialize(cells:)
          unless cells.is_a?(Integer) && !cells.negative?
            raise ArgumentError, "Fixed expects a non-negative Integer, got #{cells.inspect}"
          end

          super
        end

        # @api private
        # @param _available [Integer]
        # @return [Integer] {#cells}.
        def resolve(_available) = cells
      end

      # A percentage of the space *available* along a {Box}'s axis — measured
      # after {Box#padding} and {Box#spacing} have come off, so two `Percent[50]`
      # children fit exactly rather than overflowing by the gap between them.
      #
      #   add(left, Percent[60])
      #   add(right, Percent[40])
      #
      # @!attribute [r] percent
      #   @return [Numeric] percentage of the available extent, `0..100`.
      class Percent < Data.define(:percent)
        include Constraint

        # @param percent [Numeric] percentage of the available extent, `0..100`.
        # @raise [ArgumentError] unless `percent` is a Numeric in `0..100`.
        def initialize(percent:)
          unless percent.is_a?(Numeric) && percent.between?(0, 100)
            raise ArgumentError, "Percent expects a Numeric in 0..100, got #{percent.inspect}"
          end

          super
        end

        # Bounds the cells this share resolves to:
        #
        #   add(sidebar, Percent[33].clamp(..16))    # a third, never over 16
        #   add(list, Percent[33].clamp(20..40))     # a third, within 20..40
        #
        # The floor is best-effort: a {Box} still clamps the result to what is
        # unassigned, so an over-subscribed box starves a clamped child like any
        # other.
        # @param range [Range] inclusive, non-negative Integer endpoints, either
        #   one `nil` for unbounded.
        # @raise [ArgumentError] on an unusable `range`.
        # @return [Clamp]
        def clamp(range) = Clamp[self, range]

        # @api private
        # @param available [Integer]
        # @return [Integer] {#percent} of `available`, rounded.
        def resolve(available) = (available * percent / 100.0).round
      end

      # A share of whatever a {Box} has left once its {Fixed} and {Percent}
      # children have taken theirs, split between the `Expand` children in
      # proportion to their weights:
      #
      #   add(header, Fixed[1])
      #   add(body, Expand[2])    # gets twice…
      #   add(side, Expand[1])    # …what this one gets
      #
      # Main axis only — {Box#add} rejects one passed as `cross:`, where a child
      # has no siblings to compete with and so nothing for a weight to mean.
      #
      # @!attribute [r] weight
      #   @return [Integer] relative share of the leftover space.
      class Expand < Data.define(:weight)
        include Constraint

        # @param weight [Integer] relative share; `>= 1`.
        # @raise [ArgumentError] unless `weight` is a positive Integer.
        def initialize(weight:)
          unless weight.is_a?(Integer) && weight.positive?
            raise ArgumentError, "Expand expects a positive Integer weight, got #{weight.inspect}"
          end

          super
        end

        # @api private
        # @param _available [Integer]
        # @return [nil] an Expand has no size of its own — see {Constraint#resolve}.
        def resolve(_available) = nil
      end

      # A {Percent} whose cells are bounded by {#range} — what {Percent#clamp}
      # builds, and the way to say "half the width, but never more than 60
      # columns":
      #
      #   add(system, Percent[50].clamp(..60))
      #
      # Only a {Percent}: a {Fixed} is already exact, one range already carries
      # both bounds, and an {Expand}'s share depends on its siblings, so capping
      # it would have to hand cells back to them.
      #
      # @!attribute [r] percent
      #   @return [Percent] the share being bounded.
      # @!attribute [r] range
      #   @return [Range] the inclusive bounds, in cells.
      class Clamp < Data.define(:percent, :range)
        include Constraint

        # @param percent [Percent]
        # @param range [Range] see {Percent#clamp}.
        # @raise [ArgumentError] unless `percent` is a {Percent}; see {Percent#clamp}.
        def initialize(percent:, range:)
          raise ArgumentError, "Clamp expects a Percent, got #{percent.inspect}" unless percent.is_a?(Percent)

          validate_range(range)
          super
        end

        # @api private
        # @param available [Integer]
        # @return [Integer] {#percent}'s cells, clamped to {#range}.
        def resolve(available) = percent.resolve(available).clamp(range)

        private

        # @param range [Object]
        # @raise [ArgumentError] unless an inclusive Range of non-negative
        #   Integers (or `nil`s), ascending, bounded on at least one end.
        # @return [void]
        def validate_range(range)
          valid = range.is_a?(Range) && !range.exclude_end? &&
                  [range.begin, range.end].all? { _1.nil? || (_1.is_a?(Integer) && !_1.negative?) } &&
                  !(range.begin.nil? && range.end.nil?) &&
                  (range.begin.nil? || range.end.nil? || range.begin <= range.end)
          return if valid

          raise ArgumentError, "clamp expects an inclusive Range of non-negative Integers bounded on " \
                               "at least one end, like ..60 or 20..40, got #{range.inspect}"
        end
      end

      # Per-edge padding for a {Box}, in cells:
      #
      #   Insets[top: 1]                     # one blank row above the children
      #   Insets[top: 1, left: 2, right: 2]  # unnamed edges default to 0
      #   Insets.coerce(1)                   # uniform on all four edges
      #
      # Keyword-only: AWT and JavaFX order these same four numbers differently,
      # so a positional form would be a coin flip.
      #
      # @!attribute [r] top
      #   @return [Integer] cells inset from the top edge.
      # @!attribute [r] right
      #   @return [Integer] cells inset from the right edge.
      # @!attribute [r] bottom
      #   @return [Integer] cells inset from the bottom edge.
      # @!attribute [r] left
      #   @return [Integer] cells inset from the left edge.
      class Insets < Data.define(:top, :right, :bottom, :left)
        # @param positional [Array] must be empty — see the class doc.
        # @param kwargs [Hash{Symbol => Integer}] any of `top:`/`right:`/`bottom:`/`left:`.
        # @raise [ArgumentError] if any positional argument is given.
        # @return [Insets]
        def self.new(*positional, **kwargs)
          raise ArgumentError, "Insets is keyword-only, got #{positional.inspect}" unless positional.empty?

          super(**kwargs)
        end

        # Needed because `Data`'s inherited `[]` never dispatches through a `new`
        # override, so the guard above alone would miss `Insets[1, 2, 3, 4]`.
        # @param positional [Array] must be empty.
        # @param kwargs [Hash{Symbol => Integer}] any of `top:`/`right:`/`bottom:`/`left:`.
        # @raise [ArgumentError] if any positional argument is given.
        # @return [Insets]
        def self.[](*positional, **kwargs) = new(*positional, **kwargs)

        # @param value [Insets, Integer] an Integer becomes a uniform inset.
        # @raise [ArgumentError] on anything else, or a negative Integer.
        # @return [Insets]
        def self.coerce(value)
          return value if value.is_a?(Insets)
          unless value.is_a?(Integer) && !value.negative?
            raise ArgumentError, "expected Insets or a non-negative Integer, got #{value.inspect}"
          end

          new(top: value, right: value, bottom: value, left: value)
        end

        # @param top [Integer] cells inset from the top edge; `>= 0`.
        # @param right [Integer] cells inset from the right edge; `>= 0`.
        # @param bottom [Integer] cells inset from the bottom edge; `>= 0`.
        # @param left [Integer] cells inset from the left edge; `>= 0`.
        # @raise [ArgumentError] unless every edge is a non-negative Integer.
        def initialize(top: 0, right: 0, bottom: 0, left: 0)
          { top:, right:, bottom:, left: }.each do |edge, cells|
            unless cells.is_a?(Integer) && !cells.negative?
              raise ArgumentError, "Insets #{edge}: expected a non-negative Integer, got #{cells.inspect}"
            end
          end

          super
        end

        # @return [Integer] `left` + `right`.
        def horizontal = left + right

        # @return [Integer] `top` + `bottom`.
        def vertical = top + bottom

        # No padding on any edge.
        # @return [Insets]
        ZERO = new
      end

      # Layouts are focusable containers — like {Window} and {Popup}, they
      # don't accept input themselves but they need to participate in the
      # {HasContent} focus cascade so a Popup wrapping a Layout wrapping a
      # {TextField} ends up focusing the field rather than parking focus on
      # the popup. Layouts don't paint any visible chrome of their own
      # (the auto-cleared background is just blank space), so this has no
      # mouse-routing consequences — clicks on a gap area land back on the
      # Layout itself and the handle_focus cascade forwards to a tab stop.
      def focusable? = true

      # Adds a child component to this layout.
      # @param child [Component, Array<Component>]
      # @return [void]
      def add(child)
        if child.is_a? Enumerable
          child.each { add(_1) }
        else
          add_child(child)
        end
      end

      # @param child [Component]
      # @return [void]
      def remove(child)
        raise TypeError, "expected Component, got #{child.inspect}" unless child.is_a? Component
        raise ArgumentError, "#{child}'s parent is #{child.parent}, not this layout #{self}" if child.parent != self

        remove_child(child)
        invalidate if @children.empty? # nothing left to paint over the gap
      end

      # @return [void]
      def handle_focus
        super
        # Forward focus to the first interactive widget in the subtree so the
        # user can start typing / cursoring immediately. Prefer a {#tab_stop?}
        # descendant (TextField, List, Button…) so we skip past intermediate
        # containers like a {Window} or another {Layout}. Fall back to the
        # first focusable direct child for the rare case where the layout has
        # focusable but non-tab-stop children (e.g. an empty {Window}).
        #
        # Both halves skip hidden subtrees — this is the cascade that would
        # otherwise walk straight back into the pane just hidden.
        first_tab_stop = nil
        walk_shown_tree { |c| first_tab_stop ||= c if !c.equal?(self) && c.tab_stop? }
        if first_tab_stop
          screen.focused = first_tab_stop
        else
          first_focusable = @children.find { _1.visible? && _1.focusable? }
          screen.focused = first_focusable unless first_focusable.nil?
        end
      end
    end
  end
end
