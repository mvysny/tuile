# frozen_string_literal: true

module Tuile
  class Component
    # A layout doesn't paint anything by itself: its job is to position child
    # components. Two families, both top-down (see book ch3):
    #
    # - {Absolute} — you override {Component#rect=} and compute every child's
    #   rectangle yourself. Total control, and the base for anything unusual.
    # - {Box} / {Vertical} / {Horizontal} — you declare each child's extent as
    #   a {Fixed}, {Percent} or {Expand} constraint and the layout does the
    #   arithmetic. Sugar over the same `rect=` assignment, for the common case.
    #
    # Children that fully tile the layout's rect repaint themselves and
    # cover everything; children that leave gaps (e.g. a form with widgets
    # of varying widths) trigger {Component#repaint}'s default behavior —
    # the background is cleared and children are re-invalidated so they
    # paint over a clean surface.
    class Layout < Component
      # How much space a child gets along one axis of a {Box}: exactly {#cells},
      # clamped to whatever is still unassigned.
      #
      #   add(prompt, Fixed[4])                    # 4 rows in a Vertical
      #   add(field, Fixed[1], cross: Fixed[30])   # 1 row, 30 columns wide
      #
      # `Fixed[0]` hides the child — it gets an empty rect and paints nothing.
      #
      # @!attribute [r] cells
      #   @return [Integer] cell count along the axis.
      class Fixed < Data.define(:cells)
        # @param cells [Integer] cell count along the axis; `>= 0`.
        # @raise [ArgumentError] unless `cells` is a non-negative Integer.
        def initialize(cells:)
          unless cells.is_a?(Integer) && !cells.negative?
            raise ArgumentError, "Fixed expects a non-negative Integer, got #{cells.inspect}"
          end

          super
        end
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
        # @param percent [Numeric] percentage of the available extent, `0..100`.
        # @raise [ArgumentError] unless `percent` is a Numeric in `0..100`.
        def initialize(percent:)
          unless percent.is_a?(Numeric) && percent.between?(0, 100)
            raise ArgumentError, "Percent expects a Numeric in 0..100, got #{percent.inspect}"
          end

          super
        end
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
        # @param weight [Integer] relative share; `>= 1`.
        # @raise [ArgumentError] unless `weight` is a positive Integer.
        def initialize(weight:)
          unless weight.is_a?(Integer) && weight.positive?
            raise ArgumentError, "Expand expects a positive Integer weight, got #{weight.inspect}"
          end

          super
        end
      end

      # Per-edge padding for a {Box}, in cells:
      #
      #   Insets[top: 1]                     # one blank row above the children
      #   Insets[top: 1, left: 2, right: 2]  # unnamed edges default to 0
      #   Insets.coerce(1)                   # uniform on all four edges
      #
      # Keyword-only on purpose: the same four numbers are ordered
      # top-left-bottom-right by `java.awt.Insets` and top-right-bottom-left by
      # `javafx.geometry.Insets`, so any positional form is a coin flip.
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

        # `Data`'s own `[]` is inherited from the anonymous `Data.define` parent
        # and never dispatches through a `new` override, so the guard above would
        # miss `Insets[1, 2, 3, 4]` without this.
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
      # Layout itself and the on_focus cascade forwards to a tab stop.
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

      # Dispatches the event to the child under the mouse cursor.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        @children.each do |child|
          child.handle_mouse(event) if child.rect.contains?(event.point)
        end
      end

      # @return [void]
      def on_focus
        super
        # Forward focus to the first interactive widget in the subtree so the
        # user can start typing / cursoring immediately. Prefer a {#tab_stop?}
        # descendant (TextField, List, Button…) so we skip past intermediate
        # containers like a {Window} or another {Layout}. Fall back to the
        # first focusable direct child for the rare case where the layout has
        # focusable but non-tab-stop children (e.g. an empty {Window}).
        first_tab_stop = nil
        on_tree { |c| first_tab_stop ||= c if !c.equal?(self) && c.tab_stop? }
        if first_tab_stop
          screen.focused = first_tab_stop
        else
          first_focusable = @children.find(&:focusable?)
          screen.focused = first_focusable unless first_focusable.nil?
        end
      end

      # Absolute layout. Extend this class, register any children, and
      # override {Component#rect=} to reposition the children.
      class Absolute < Layout
      end
    end
  end
end
