# frozen_string_literal: true

module Tuile
  class Component
    class Layout
      # Where each child of one {Layout} wants to be — a {Box} child's
      # `main`/`cross`/`align`, an {Absolute} child's {Rect} — reached through
      # {Layout#constraints} and read back by the layout's {Component#relayout}:
      #
      #   def add(child, rect)
      #     add_child(child)
      #     constraints[child] = rect            # marks the layout, unless unchanged
      #   end
      #
      #   def relayout = children.each { _1.rect = constraints.fetch(_1) }
      #
      # **Only a child may be constrained**, so write the entry *after*
      # `add_child`; {Layout#remove} forgets it. A child hidden with
      # {Component#visible=} keeps its entry.
      #
      # == Implementation details
      #
      # **An attribute map, not a second copy of ordering** — hence no `each`,
      # `keys` or `size`: a `relayout` walks {Component#children}, the sole
      # ordering authority, and looks each child up here. Keys are compared by
      # identity, entries by `==`.
      #
      # A child detached other than through {Layout#remove} — a subclass calling
      # `remove_child` itself — leaves its entry behind, to be found again should
      # that component come back.
      class ConstraintMap
        # @param owner [Layout] the layout whose children this maps.
        def initialize(owner)
          @owner = owner
          @entries = {}.compare_by_identity # two == children are two slots
        end

        # @param child [Component]
        # @return [Object, nil] the child's entry; nil when none was written.
        def [](child) = @entries[child]

        # @param child [Component]
        # @return [Object] the child's entry.
        # @raise [KeyError] when none was written.
        def fetch(child)
          @entries.fetch(child) { raise KeyError, "#{child} has no constraints in #{@owner}" }
        end

        # Constrains a child and marks the owner as owing a
        # {Component#relayout}; writing the entry it already has marks nothing.
        # @param child [Component] a child of the owner.
        # @param value [Object] the layout's own shape — a `Hash`, a {Rect}.
        # @raise [ArgumentError] if `child` is not a child of the owner.
        # @return [void]
        def []=(child, value)
          raise ArgumentError, "#{child} is not a child of #{@owner}" unless child.parent.equal?(@owner)
          return if @entries.key?(child) && @entries[child] == value

          @entries[child] = value
          # Protected; the map is the layout's own bookkeeping, not a caller's.
          @owner.__send__(:invalidate_layout)
        end

        # Forgets a child's entry. Marks nothing: the removal that calls this
        # already did.
        # @param child [Component]
        # @return [void]
        def delete(child)
          @entries.delete(child)
        end
      end
    end
  end
end
