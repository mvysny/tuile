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

    # Drain rounds a {Screen#flush_layout} or a detached {Component#flush_layout}
    # runs before giving up. No container sizes itself from its children, so a
    # tree settles in about its depth; one that is still marking past this is
    # feeding a pass's output back into its input — a {Component::Scroller}
    # whose `content_rows` the app derives from the content's width, say — and
    # would otherwise hang the UI thread.
    # @return [Integer]
    MAX_ROUNDS = 50

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

    # Whether any pass is placing children right now — what a drain refuses to
    # run inside ({.refuse_nested}), and {Screen#focused=} defers its geometry under.
    # @return [Boolean]
    def running? = !Thread.current[PLACING].nil?

    # The guard at the top of both drains, {Screen#flush_layout} and a detached
    # {Component#flush_layout}.
    # @raise [Tuile::Error] while a pass is running: it has not placed its
    #   children yet, so a nested drain would read the rects it is about to
    #   reassign.
    # @return [void]
    def refuse_nested
      return unless running?

      raise Tuile::Error, "flush_layout inside #{Thread.current[PLACING]}'s relayout: the running pass " \
                          "has not placed its children yet, so a nested drain would read stale rects"
    end

    # What may assign `component`'s rect: its parent, whose
    # {Component#relayout} does. The exception is the {ScreenPane}, which has
    # no parent whose pass could place it, so the {Screen} does (`D_tree_first`
    # keeps the screen out of the tree). Those are the only two cases — this is
    # a closed rule rather than a hook a component may answer for itself.
    # @param component [Component]
    # @return [Component, Screen, nil]
    def placer(component)
      component.is_a?(ScreenPane) ? component.screen : component.parent
    end

    # @param component [Component] the one whose rect is being assigned.
    # @raise [Tuile::Error] unless {.placer} is what is placing now.
    # @return [void]
    def check(component)
      current = Thread.current[PLACING]
      return if !current.nil? && current.equal?(placer(component))

      if component.parent.nil?
        raise Tuile::Error, "#{component} has no parent to place it; to size a detached tree, " \
                            "hold it in a Layout::Absolute (add(tree, rect), then flush_layout)"
      end
      raise Tuile::Error, "#{component}'s rect assigned outside #{component.parent}'s relayout; change " \
                          "what the parent places it by instead (Absolute#constrain, Box#constrain, " \
                          "Overlay#placement=)"
    end

    # Runs every {Component#relayout} `root`'s tree owes, to a fixpoint — the one
    # drain behind both {Screen#flush_layout} and a detached
    # {Component#flush_layout}.
    #
    # **The dirty flags are the queue.** Each round walks the tree pre-order and
    # runs whatever is marked, so a parent lays out before the children whose
    # rects it just wrote, and those children run in the same walk. A mark on
    # something *earlier* in the order — a child's pass marking its parent —
    # waits for the next round, and the drain ends on the first walk that finds
    # nothing marked. A flag is cleared by the pass that answers it, so a
    # container is never run twice for one mark, and a raise strands nothing.
    # @param root [Component] the tree's root: the {ScreenPane}, or a detached root.
    # @param rounds [Integer] rounds already run in this flush, so a caller
    #   draining more than once — the screen, re-checking anchors — keeps one count.
    # @raise [Tuile::Error] past {MAX_ROUNDS} rounds, naming the containers still marked.
    # @return [Integer] the rounds run in total.
    def drain(root, rounds = 0)
      while drain_round(root)
        next rounds += 1 if rounds < MAX_ROUNDS

        culprits = []
        root.walk_tree { culprits << _1 if _1.layout_dirty? }
        raise Tuile::Error, "layout did not settle after #{MAX_ROUNDS} rounds, still marking: " \
                            "#{culprits.first(5).map(&:inspect).join(", ")} — a relayout keeps changing its " \
                            "own input (content_rows derived from the content's width?)"
      end
      rounds
    end

    # One pre-order walk running every marked container.
    # @param root [Component]
    # @return [Boolean] whether it ran anything.
    def drain_round(root)
      ran = false
      root.walk_tree do |component|
        next unless component.layout_dirty?

        # `__send__`: private, because it is this drain's alone.
        component.__send__(:perform_relayout)
        ran = true
      end
      ran
    end
    private_class_method :drain_round

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
