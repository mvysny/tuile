# frozen_string_literal: true

module Tuile
  class Component
    # A one-child region: a place in the tree reserved for content that may be
    # absent, arrive late, or be swapped. The occupant fills the slot's {#rect}.
    #
    # Wire one per region at construction, then swap occupants through
    # {HasContent#content=} — which is how {Window} holds its footer:
    #
    #   @footer_slot = Slot.new
    #   add_child(@footer_slot)             # the region, wired once
    #   …
    #   @footer_slot.content = new_footer   # the occupant, swapped at will
    #
    # Because the slot never leaves {Component#children}, a swap's insert index
    # is always 0 — never a function of which *other* regions happen to be
    # occupied, which is the whole reason to reach for one (`D_slots`).
    #
    # An empty slot does not collapse: it keeps its rect and clears it, so a
    # dialog with no message shows the hole. Close the gap with a zero extent
    # from the parent, or assign an empty {Rect} to suppress the clear entirely
    # (what {Window} does with an absent footer); never detach it.
    #
    # Transparent to input: not {Component#focusable?},
    # {Component#handle_mouse} descends through it, and a departing occupant's
    # focus repair is handed to the container.
    class Slot < Component
      include Component::HasContent

      # @param content [Component, nil] the initial occupant.
      def initialize(content = nil)
        super()
        @content = nil
        self.content = content unless content.nil?
      end

      # Hands the repair to the container rather than doing it here: the default
      # would move focus to `self`, and a slot is inert — no cursor, no keys,
      # nothing to bubble from.
      # @param child [Component] the just-detached occupant.
      # @return [void]
      def on_child_removed(child)
        parent&.on_child_removed(child)
      end

      protected

      # @param content [Component]
      # @return [void]
      def layout(content) = content.rect = rect
    end
  end
end
