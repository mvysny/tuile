# frozen_string_literal: true

module Tuile
  module Mouse
    # Delivers {Mouse::Event}s to the component tree. {Screen} owns one and hands
    # it every parsed event; components never walk the tree for the mouse
    # themselves, they only answer the handlers it calls:
    #
    #   screen.handle_mouse(Mouse::DownEvent.new(:left, 5, 2))   # what the loop does
    #
    # | event | delivered to |
    # |---|---|
    # | {DownEvent} | {Component#handle_mouse_down?}, bubbling from the innermost
    #   component under the pointer until one claims it — and the claimant is
    #   then {#grabbed} |
    # | {ScrollEvent} | {Component#handle_mouse_scroll?}, bubbling the same way |
    # | {MoveEvent} | {Component#handle_mouse_move?}, bubbling the same way;
    #   enter/exit fire first. `:hover` only |
    # | {DragEvent} / {UpEvent} | {Component#handle_mouse_drag} /
    #   {Component#handle_mouse_up} on {#grabbed} alone; an up ends the grab |
    #
    # The walk starts at the topmost popup containing the point, else at the
    # tiled content unless a modal popup is open ({ScreenPane#mouse_root_at}),
    # and descends through shown children whose {Component#rect} contains the
    # point. A left press first focuses the innermost {Component#focusable?} on
    # that path — geometry-ungated, so a widget's dead tail still focuses it —
    # while the handlers bubble only along the prefix whose
    # {Component#extent_rect} contains the point (`D_extent`).
    #
    # UI-thread-confined.
    #
    # == Implementation details
    #
    # **The grab has three releases and no relinquishing**: the up, the next
    # down (the up was lost — ssh and tmux do lose them), and any key
    # ({#release_grab}). None of the last two tells the grabbed component. Hiding
    # or detaching it does not end the grab either; the router just stops
    # delivering to it until the release (`D_mouse_dispatch`).
    #
    # **The hovered chain is synced, not toggled**: a move re-resolves it and
    # diffs, and {#sync_hover} — run by {Screen#repaint} — drops members that
    # were detached, hidden or reparented since, firing their exits.
    class Router
      # @param screen [Screen]
      def initialize(screen)
        @screen = screen
        @level = :hover
        @hovered = []
        @grabbed = nil
        @grab_button = nil
      end

      # @return [Symbol, nil] the tracking level the terminal was asked for —
      #   one of {Mouse::LEVELS}. A move is dropped below `:hover`, since under
      #   `:drag` it only reports an unclaimed press being dragged. `:hover`
      #   outside an event loop, so a spec may post any event.
      attr_accessor :level

      # @return [Component, nil] the component whose {Component#handle_mouse_down?}
      #   claimed the press still held.
      attr_reader :grabbed

      # @return [Component, nil] the innermost component under the pointer, as of
      #   the last move under `:hover`.
      def hovered = @hovered.last

      # @param event [Mouse::Event]
      # @return [void]
      def dispatch(event)
        case event
        when DownEvent then press(event)
        when UpEvent then release(event)
        when ScrollEvent then bubble(extent_path(event.point), :handle_mouse_scroll?, event)
        when MoveEvent then move(event)
        end
      end

      # Ends the grab without telling the grabbed component.
      # @return [void]
      def release_grab
        @grabbed = nil
        @grab_button = nil
      end

      # Drops the hovered-chain members that are no longer attached, shown, or
      # children of the member before them, firing
      # {Component#handle_mouse_exit} innermost first. Idempotent.
      # @return [void]
      def sync_hover
        valid = @hovered.each_with_index.take_while do |c, i|
          c.attached? && c.visible? && (i.zero? || c.parent.equal?(@hovered[i - 1]))
        end.size
        return if valid == @hovered.size

        rehover(@hovered.take(valid))
      end

      private

      # @param event [DownEvent]
      # @return [void]
      def press(event)
        release_grab
        point = event.point
        pane = @screen.pane
        root = pane.mouse_root_at(point)
        path = rect_path(root, point)
        pane.dismissing_popups_outside(point, left: event.button == :left) do
          focus_innermost(root, path) if event.button == :left
          claimant = bubble(path.take_while { _1.extent_rect.contains?(point) }, :handle_mouse_down?, event)
          unless claimant.nil?
            @grabbed = claimant
            @grab_button = event.button
          end
        end
      end

      # @param event [UpEvent]
      # @return [void]
      def release(event)
        grabbed = @grabbed
        release_grab
        grabbed.__send__(:handle_mouse_up, event) if reachable?(grabbed)
      end

      # @param event [MoveEvent]
      # @return [void]
      def move(event)
        unless @grabbed.nil?
          drag = DragEvent.new(@grab_button, event.x, event.y)
          @grabbed.__send__(:handle_mouse_drag, drag) if reachable?(@grabbed)
          return
        end
        return unless @level == :hover

        path = extent_path(event.point)
        rehover(path)
        bubble(path, :handle_mouse_move?, event)
      end

      # A non-modal overlay is never focused into: it sits outside the key scope,
      # so focus there would make every keystroke go dead (`D_overlay`).
      # @param root [Component, nil]
      # @param path [Array<Component>]
      # @return [void]
      def focus_innermost(root, path)
        return if root.is_a?(Component::Overlay) && !root.modal?

        target = path.reverse_each.find(&:focusable?)
        @screen.focused = target unless target.nil? || target.active?
      end

      # @param path [Array<Component>] root first.
      # @param handler [Symbol] a routed `handle_mouse_…?`.
      # @param event [Mouse::Event]
      # @return [Component, nil] the component that answered true.
      def bubble(path, handler, event)
        # A handler may detach what is below it on the path (a click that swaps
        # a slot's occupant), so re-check before each delivery.
        path.reverse_each.find { |c| c.attached? && c.__send__(handler, event) }
      end

      # @param point [Point]
      # @return [Array<Component>] the shown components under `point` whose
      #   extent contains it, root first.
      def extent_path(point)
        rect_path(@screen.pane.mouse_root_at(point), point).take_while { _1.extent_rect.contains?(point) }
      end

      # @param root [Component, nil]
      # @param point [Point]
      # @return [Array<Component>] the shown components whose rect contains
      #   `point`, root first. Tiled siblings never overlap, so at most one child
      #   qualifies at each level.
      def rect_path(root, point)
        path = []
        component = root
        while component&.visible? && component.rect.contains?(point)
          path << component
          component = component.children.find { _1.visible? && _1.rect.contains?(point) }
        end
        path
      end

      # @param chain [Array<Component>] the new hovered chain, root first.
      # @return [void]
      def rehover(chain)
        old = @hovered
        @hovered = chain
        (old - chain).reverse_each { _1.__send__(:handle_mouse_exit) }
        (chain - old).each { _1.__send__(:handle_mouse_enter) }
      end

      # @param component [Component, nil]
      # @return [Boolean] whether `component` is attached and it and every
      #   ancestor are shown.
      def reachable?(component)
        return false if component.nil? || !component.attached?

        cursor = component
        cursor = cursor.parent while cursor&.visible?
        cursor.nil?
      end
    end
  end
end
