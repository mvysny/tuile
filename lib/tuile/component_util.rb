# frozen_string_literal: true

module Tuile
  # Pure queries over the component tree, as module functions:
  #
  #   ComponentUtil.effectively_visible?(field)   # false under a hidden panel
  #
  # Home for a question that belongs to no one component and to no one asker.
  # Deliberately **not** {Component} methods, for the reason `D_empty_ancestor`
  # declined a `Component#paintable?`: each reads as a component-level concept
  # and is really the framework's question.
  #
  # **The gate for a new member** is a pure query over the tree — no state, no
  # mutation — with **two or more call sites in `lib/`**; one caller stays
  # private to the class that asks. Without it this becomes the drawer internal
  # things go in.
  #
  # Tuile-internal: a member may change or vanish with no migration note, and
  # one an app turns out to need graduates to a documented home instead.
  #
  # @api private
  module ComponentUtil
    module_function

    # Whether `component` is genuinely on screen: attached, with neither it nor
    # any ancestor hidden. {Component#visible?} is a component's own flag alone,
    # so a field under a hidden panel is still `visible?` itself.
    #
    # A *walk* needs no such predicate — it prunes at the hidden subtree's root
    # ({Component#walk_shown_tree}).
    # @param component [Component]
    # @raise [TypeError] on `nil` — a caller that may hold one says so itself,
    #   rather than having "no component" quietly answer "not visible".
    # @return [Boolean]
    def effectively_visible?(component)
      raise TypeError, "expected Component, got nil" if component.nil?

      cursor = component
      cursor = cursor.parent while cursor&.visible?
      cursor.nil? && component.attached?
    end

    # `child`'s {Component#measure_rows}, with absent or hidden content counting
    # `0` — the answer a component passing one child's rows on owes:
    #
    #   def measure_rows(width) = ComponentUtil.measure_rows_of(content, width)
    #
    # Hidden is *gone* (`D_visibility`), so it answers as absent; and absent fills
    # nothing, so it is `0` rather than the `nil` that means "I fill".
    # @param child [Component, nil] `nil` is absent content, not an error.
    # @param width [Integer]
    # @return [Integer, nil] `nil` only when a shown child answers `nil`.
    def measure_rows_of(child, width) = child&.visible? ? child.measure_rows(width) : 0
  end
end
