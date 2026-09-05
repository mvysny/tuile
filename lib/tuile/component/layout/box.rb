# frozen_string_literal: true

module Tuile
  class Component
    class Layout
      # Abstract base of the one-dimensional box layouts. Children are stacked
      # along a *main* axis in the order they were added, each getting the extent
      # its constraint asks for; across the *cross* axis they are sized one at a
      # time, since nothing competes with them there. {Vertical} and {Horizontal}
      # pick which axis is which.
      #
      #   class LoginForm < Tuile::Component::Layout::Vertical
      #     def initialize
      #       super(spacing: 1, padding: Insets[top: 1])
      #       add(@prompt = Tuile::Component::Label.new, Fixed[4])
      #       add(@user = Tuile::Component::TextField.new, Fixed[1], cross: Fixed[30])
      #       add(@log = Tuile::Component::TextView.new, Expand[1])
      #     end
      #   end
      #
      # The constraint names need no prefix inside a subclass — Ruby finds them on
      # `Layout`, an ancestor. Component classes are not on that chain and still do.
      #
      # Children pack from the start edge, so with no {Expand} among them the
      # slack is simply left at the end: there is no filler component to add.
      # Nest boxes to vary the gap — a `Vertical.new(spacing: 0)` inside a
      # `Vertical.new(spacing: 1)` groups two rows tightly within a looser stack.
      #
      # **Hiding a pane is {#remove}, not `Fixed[0]`** (see {Fixed} for why an
      # empty rect is not hiding). {#add}'s `at:` is what makes it reversible —
      # keep the index and the constraints on your side:
      #
      #   remove(@sidebar)                    # hide: siblings reclaim the space
      #   add(@sidebar, Expand[1], at: 0)     # show: back where it was
      #
      # == Implementation details
      #
      # Every child-list mutation re-runs the whole pass, because in a box the
      # children move: removing one shifts everything after it, and adding one
      # shrinks every {Expand} share. ({Absolute} can skip this — there, siblings
      # are independent.)
      #
      # Main-axis resolution order, against
      # `available = extent - padding - spacing * (children - 1)`:
      #
      # 1. {Fixed} takes its cells, clamped to what is still unassigned.
      # 2. {Percent} takes its share *of `available`*, likewise clamped.
      # 3. {Expand} children split the residue by weight; the integer remainder
      #    goes to the earliest of them, one cell each.
      #
      # So over-subscription starves in declaration order rather than raising:
      # a child with nothing left gets an empty rect and paints nothing. Padding
      # wider than the layout does the same to every child.
      class Box < Layout
        # Constraints for a child wired in through `add_child` instead of {#add}.
        # @return [Hash{Symbol => Object}]
        DEFAULT_PLACEMENT = { main: Fixed[1], cross: Percent[100], align: :start }.freeze

        # Where a child narrower than the cross extent sits within it.
        # @return [Array<Symbol>]
        ALIGNMENTS = %i[start center end].freeze

        # @param spacing [Integer] blank cells between adjacent children; `>= 0`.
        # @param padding [Insets, Integer] inset from this layout's own rect; an
        #   Integer is coerced to a uniform {Insets}.
        # @raise [ArgumentError] on a negative `spacing` or an unusable `padding`.
        def initialize(spacing: 0, padding: 0)
          super()
          @spacing = validate_spacing(spacing)
          @padding = Insets.coerce(padding)
          # Identity-keyed: two == children are still two distinct slots.
          @placements = {}.compare_by_identity
        end

        # @return [Integer] blank cells between adjacent children.
        attr_reader :spacing

        # @return [Insets] inset from this layout's own rect.
        attr_reader :padding

        # @param cells [Integer] blank cells between adjacent children; `>= 0`.
        # @raise [ArgumentError] on a negative value.
        # @return [void]
        def spacing=(cells)
          cells = validate_spacing(cells)
          return if @spacing == cells

          @spacing = cells
          relayout
        end

        # @param insets [Insets, Integer] an Integer becomes a uniform inset.
        # @raise [ArgumentError] on anything else.
        # @return [void]
        def padding=(insets)
          insets = Insets.coerce(insets)
          return if @padding == insets

          @padding = insets
          relayout
        end

        # Adds a child — or every element of an Enumerable, all with the same
        # constraints — and re-runs the layout.
        #
        #   add(field, Fixed[1], cross: Fixed[30], align: :center)
        #   add([ok, cancel], Fixed[1])
        #   add(sidebar, Expand[1], at: 0)   # back where it was, after a #remove
        #
        # @param child [Component, Enumerable<Component>]
        # @param main [Fixed, Percent, Expand] extent along the main axis.
        # @param cross [Fixed, Percent] extent across it.
        # @param align [Symbol] one of {ALIGNMENTS} — where a child narrower than
        #   the cross extent sits. {Vertical} / {Horizontal} say which edge
        #   `:start` is.
        # @param at [Integer, nil] position among the existing children; appends
        #   when nil. An Enumerable is inserted in order from there. This is what
        #   makes hiding-by-{#remove} reversible — see the class doc.
        # @raise [ArgumentError] on an unknown constraint or alignment, or an
        #   {Expand} passed as `cross` (see {Expand}).
        # @raise [TypeError] if `child` is not a {Component}.
        # @return [void]
        def add(child, main = Fixed[1], cross: Percent[100], align: :start, at: nil)
          if child.is_a? Enumerable
            child.each_with_index { |c, i| add(c, main, cross:, align:, at: at && at + i) }
            return
          end

          validate_main(main)
          validate_cross(cross)
          validate_align(align)
          add_child(child, at:)
          @placements[child] = { main:, cross:, align: }
          relayout
        end

        # Re-constrains a child already in the layout and re-runs the pass. A
        # `nil` argument keeps what that axis already had, so one can move alone:
        #
        #   box.constrain(sidebar, Fixed[0])   # collapse it; cross: and align: stand
        #
        # `Fixed[0]` *collapses* — see {Fixed} for why that is not the same as
        # hiding, and the class doc for what is.
        #
        # @param child [Component] a child of this layout.
        # @param main [Fixed, Percent, Expand, nil] extent along the main axis.
        # @param cross [Fixed, Percent, nil] extent across it.
        # @param align [Symbol, nil] one of {ALIGNMENTS}.
        # @raise [ArgumentError] if `child` is not a child of this layout, or on
        #   an unknown constraint or alignment.
        # @return [void]
        def constrain(child, main = nil, cross: nil, align: nil)
          raise ArgumentError, "#{child} is not a child of #{self}" unless children.any? { _1.equal?(child) }

          validate_main(main) unless main.nil?
          validate_cross(cross) unless cross.nil?
          validate_align(align) unless align.nil?

          current = placement(child)
          updated = { main: main || current[:main], cross: cross || current[:cross],
                      align: align || current[:align] }
          return if current == updated

          @placements[child] = updated
          relayout
        end

        # Removes the child, forgets its constraints, and closes the gap it left
        # by re-running the layout.
        # @param child [Component]
        # @return [void]
        def remove(child)
          super
          @placements.delete(child)
          relayout
        end

        # @param new_rect [Rect]
        # @return [void]
        def rect=(new_rect)
          super
          relayout
        end

        protected

        # Re-divides the space: a child that just went hidden gives its slot
        # *and* the {#spacing} around it back to its siblings, and one that came
        # back takes them again with the constraints it was added with — which
        # is what {Component#visible=} buys over `remove` plus `add(…, at:)`.
        # @param _child [Component]
        # @return [void]
        def on_child_visibility_changed(_child) = relayout

        private

        # Recomputes and assigns every child's rect, giving each an empty one
        # when this layout's own rect — or {#inner_rect} — is empty.
        #
        # Deliberately *no* `return if rect.empty?` guard: that strands the
        # children at the coordinates they last had, and the next full repaint
        # paints them there (`D_empty_ancestor`). Construction is silent without
        # one anyway — {#add} runs before a parent assigns a rect, so the
        # children are already empty and `invalidate` no-ops while detached.
        # @return [void]
        def relayout
          inner = inner_rect
          collapsed = Rect.new(rect.left, rect.top, 0, 0)
          if rect.empty? || inner.empty?
            children.each { _1.rect = collapsed }
          else
            children.each { _1.rect = collapsed unless _1.visible? }
            place_children(inner)
          end
          invalidate
        end

        # @return [Rect] {#rect} with {#padding} taken off each edge; may be
        #   {Rect#empty? empty}.
        def inner_rect
          Rect.new(rect.left + padding.left, rect.top + padding.top,
                   rect.width - padding.horizontal, rect.height - padding.vertical)
        end

        # @param inner [Rect] {#inner_rect}, known non-empty.
        # @return [void]
        def place_children(inner)
          kids = shown_children
          sizes = main_sizes(inner, kids)
          available = cross_extent(inner)
          offset = 0
          kids.each_with_index do |child, i|
            cross_offset, cross_size = cross_placement(child, available)
            child.rect = build_rect(inner, offset, sizes[i], cross_offset, cross_size)
            offset += sizes[i] + spacing
          end
        end

        # The children this pass divides space between. A hidden child is not
        # one of them — it is out of the {#spacing} count as well as out of the
        # arithmetic, so hiding a middle child closes the row up completely
        # rather than leaving a double gap where it was (`D_visibility`; every
        # box layout surveyed prices spacing over shown children only). Note the
        # contrast with a `Fixed[0]` child, which *is* still a member of the
        # sequence and keeps costing its gap.
        # @return [Array<Component>]
        def shown_children = children.select(&:visible?)

        # @param inner [Rect] {#inner_rect}.
        # @param kids [Array<Component>] {#shown_children}.
        # @return [Array<Integer>] main-axis extent per shown child, in order.
        def main_sizes(inner, kids)
          count = kids.size
          return [] if count.zero?

          available = [main_extent(inner) - (spacing * (count - 1)), 0].max
          sizes = Array.new(count, 0)
          expanding = []
          unassigned = available

          kids.each_with_index do |child, i|
            case (constraint = placement(child)[:main])
            when Expand then expanding << i
            when Fixed then unassigned -= (sizes[i] = constraint.cells.clamp(0, unassigned))
            else unassigned -= (sizes[i] = percent_of(available, constraint).clamp(0, unassigned))
            end
          end

          distribute_expand(sizes, kids, expanding, unassigned) unless expanding.empty?
          sizes
        end

        # Splits `slack` between the {Expand} children by weight, writing the
        # results into `sizes`.
        # @param sizes [Array<Integer>] mutated in place.
        # @param kids [Array<Component>] {#shown_children}, which `indices` index.
        # @param indices [Array<Integer>] child indices carrying an {Expand}.
        # @param slack [Integer] cells left over; a negative value yields zeroes.
        # @return [void]
        def distribute_expand(sizes, kids, indices, slack)
          slack = 0 if slack.negative?
          weights = indices.map { placement(kids[_1])[:main].weight }
          total = weights.sum
          shares = weights.map { slack * _1 / total }
          # Under one cell is lost per floor, so the remainder can't outrun the
          # share count — the earliest Expand children each take one.
          (slack - shares.sum).times { |i| shares[i] += 1 }
          indices.each_with_index { |child_index, i| sizes[child_index] = shares[i] }
        end

        # @param child [Component]
        # @param available [Integer] cross extent of {#inner_rect}.
        # @return [Array(Integer, Integer)] offset from `inner`'s start edge, and
        #   extent, along the cross axis.
        def cross_placement(child, available)
          spec = placement(child)
          size = case (constraint = spec[:cross])
                 when Fixed then constraint.cells.clamp(0, available)
                 else percent_of(available, constraint).clamp(0, available)
                 end
          [align_offset(spec[:align], available - size), size]
        end

        # @param align [Symbol] one of {ALIGNMENTS}.
        # @param slack [Integer] unused cells across the axis.
        # @return [Integer]
        def align_offset(align, slack)
          case align
          when :center then slack / 2
          when :end then slack
          else 0
          end
        end

        # @param extent [Integer]
        # @param constraint [Percent]
        # @return [Integer]
        def percent_of(extent, constraint) = (extent * constraint.percent / 100.0).round

        # @param child [Component]
        # @return [Hash{Symbol => Object}] the child's `main`/`cross`/`align`.
        def placement(child) = @placements[child] || DEFAULT_PLACEMENT

        # @param rect [Rect]
        # @return [Integer] the extent along the main axis.
        def main_extent(rect) = raise(NotImplementedError, "#{self.class} must implement main_extent")

        # @param rect [Rect]
        # @return [Integer] the extent along the cross axis.
        def cross_extent(rect) = raise(NotImplementedError, "#{self.class} must implement cross_extent")

        # @param inner [Rect] {#inner_rect}, the origin both offsets are relative to.
        # @param main_offset [Integer] cells along the main axis.
        # @param main_size [Integer] extent along the main axis.
        # @param cross_offset [Integer] cells along the cross axis.
        # @param cross_size [Integer] extent along the cross axis.
        # @return [Rect] absolute screen rect for one child.
        def build_rect(inner, main_offset, main_size, cross_offset, cross_size)
          raise NotImplementedError, "#{self.class} must implement build_rect"
        end

        # @param cells [Integer]
        # @raise [ArgumentError] unless `cells` is a non-negative Integer.
        # @return [Integer] `cells`.
        def validate_spacing(cells)
          unless cells.is_a?(Integer) && !cells.negative?
            raise ArgumentError, "spacing expects a non-negative Integer, got #{cells.inspect}"
          end

          cells
        end

        # @param constraint [Object]
        # @raise [ArgumentError] unless it is a {Fixed}, {Percent} or {Expand}.
        # @return [void]
        def validate_main(constraint)
          return if [Fixed, Percent, Expand].any? { constraint.is_a?(_1) }

          raise ArgumentError, "expected Fixed, Percent or Expand, got #{constraint.inspect}"
        end

        # @param constraint [Object]
        # @raise [ArgumentError] unless it is a {Fixed} or {Percent}.
        # @return [void]
        def validate_cross(constraint)
          if constraint.is_a? Expand
            raise ArgumentError, "Expand is main-axis only — a child has no siblings competing " \
                                 "across the axis; use Fixed or Percent for cross:"
          end
          return if constraint.is_a?(Fixed) || constraint.is_a?(Percent)

          raise ArgumentError, "expected Fixed or Percent for cross:, got #{constraint.inspect}"
        end

        # @param align [Object]
        # @raise [ArgumentError] unless it is one of {ALIGNMENTS}.
        # @return [void]
        def validate_align(align)
          return if ALIGNMENTS.include?(align)

          raise ArgumentError, "expected one of #{ALIGNMENTS.inspect}, got #{align.inspect}"
        end
      end
    end
  end
end
