# frozen_string_literal: true

module Tuile
  class Component
    # A one-child region: a place in the tree reserved for content that may be
    # absent, arrive late, or be swapped. The content fills the slot's {#rect}.
    #
    # A container with several regions gives each one a slot, wired once at
    # construction, and swaps occupants through {HasContent#content=}:
    #
    #   def initialize
    #     super
    #     @message = Slot.new
    #     add(@message, Layout::Expand[1])
    #     add(button_row, Layout::Fixed[1])
    #   end
    #
    #   def message=(text) = @message.content = Label.new(text)
    #
    # That is the point of the class: because the slot itself never leaves
    # {Component#children}, the insert index for a swap is always 0 and never
    # depends on which *other* regions happen to be occupied. Reaching for
    # {HasContent} on the container instead would give it a single `content`
    # while it really has several children, and its routing would then ignore
    # all but one of them.
    #
    # An empty slot does not collapse — it keeps the rect its parent assigned
    # and clears it, so a dialog with no message shows the hole rather than
    # reflowing. Give it a zero extent to close the gap; never detach it, which
    # would put the index arithmetic back. Assign an empty {Rect} to suppress
    # the clear entirely, as a {Window} does with an absent footer.
    #
    # Transparent to input: not {Component#focusable?}, so the focus cascades
    # walk past it to the real widget, {Component#handle_mouse} descends through
    # it, and a departing occupant's focus repair is handed to the container.
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
