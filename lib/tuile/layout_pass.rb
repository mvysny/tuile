# frozen_string_literal: true

module Tuile
  # Who may assign a rect right now. {Component#rect=} is refused outside the
  # parent's {Component#relayout}, and this is the bracket that says when one
  # is running:
  #
  #   LayoutPass.run(container) { relayout }    # inside the container
  #
  # A pass also records whether it has placed a child *yet*, which is what lets
  # {Component#invalidate_layout} drop a mark a container makes on itself
  # before its first placement: the pass that would answer it is the one
  # running.
  #
  # **Thread-local rather than an ivar**, because a tree with no {Screen}
  # places children too, so there is no one object to hang the state on.
  #
  # Tuile-internal: a member may change or vanish with no migration note. The
  # rule it enforces is {Component#rect=}'s and is documented there.
  #
  # @api private
  module LayoutPass
    # The thread-local naming what is placing children right now.
    # @return [Symbol]
    PLACING = :tuile_placing
    private_constant :PLACING

    # The thread-local saying whether the current placer has assigned a child
    # rect yet.
    # @return [Symbol]
    PLACED = :tuile_placed
    private_constant :PLACED

    module_function

    # Runs the block with `placer` as the one thing whose children's rects may
    # be assigned. Nests: the enclosing pass is restored on the way out.
    # @param placer [Component, Screen]
    # @return [Object] the block's value.
    def run(placer)
      outer = Thread.current[PLACING]
      outer_placed = Thread.current[PLACED]
      Thread.current[PLACING] = placer
      Thread.current[PLACED] = false
      yield
    ensure
      Thread.current[PLACING] = outer
      Thread.current[PLACED] = outer_placed
    end

    # @param component [Component] the one whose rect is being assigned.
    # @raise [Tuile::Error] unless {Component#placer} is what is placing now.
    # @return [void]
    def check(component)
      current = Thread.current[PLACING]
      return if !current.nil? && current.equal?(component.__send__(:placer))

      if component.parent.nil?
        raise Tuile::Error, "#{component} has no parent to place it; to size a detached tree, " \
                            "hold it in a Layout::Absolute (add(tree, rect), then flush_layout)"
      end
      raise Tuile::Error, "#{component}'s rect assigned outside #{component.parent}'s relayout; change " \
                          "what the parent places it by instead (Absolute#constrain, Box#constrain, " \
                          "Overlay#placement=)"
    end

    # Records that the running pass has assigned a child rect, past which a
    # mark on the placer is kept rather than dropped.
    # @return [void]
    def note_placement
      Thread.current[PLACED] = true
    end

    # Whether `component` is the running placer and has placed no child yet —
    # the window in which a mark it makes on itself is redundant.
    # @param component [Component]
    # @return [Boolean]
    def before_first_placement?(component)
      Thread.current[PLACING].equal?(component) && !Thread.current[PLACED]
    end
  end
end
