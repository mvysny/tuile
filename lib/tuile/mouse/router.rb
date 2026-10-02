# frozen_string_literal: true

module Tuile
  module Mouse
    # Delivers {Mouse::Event}s to the component tree. {Screen} owns one and hands
    # it every event the terminal reports; a component only answers the handlers
    # it calls, and walks nothing itself.
    #
    #   screen.handle_mouse(Mouse::DownEvent.new(:left, 5, 2))   # what the loop does
    #
    # Every event resolves against one **path**: the topmost popup containing the
    # point, else the tiled content unless a modal popup is open
    # ({ScreenPane#mouse_root_at}), then down through the shown children whose
    # {Component#rect} contains it. A `rect` is parent-relative, so the walk
    # converts the point as it descends and each component is handed the event
    # in **its own** coordinates — the same ones it paints in (`D_relative_rect`).
    #
    # - **{DownEvent}** — focuses the innermost {Component#focusable?} on that
    #   path, then offers {Component#handle_mouse_down?} innermost-first until one
    #   component answers `true`. That claimant becomes {#grabbed}.
    # - **{ScrollEvent}**, **{MoveEvent}** — bubble the same way through
    #   {Component#handle_mouse_scroll?} / {Component#handle_mouse_move?}, and grab
    #   nothing. A move fires the enter/exit hooks first, and arrives only at
    #   `:hover`.
    # - **{DragEvent}**, **{UpEvent}** — skip the path entirely: they go to
    #   {#grabbed}, wherever the pointer is, and an up ends the grab.
    #
    # The two geometries are deliberately different. Focus follows `rect`, so a
    # press on the dead tail a widget does not paint still focuses it; the
    # handlers bubble only along the prefix whose
    # {Component#local_extent_rect} contains the point, so that same press
    # activates nothing (`D_extent`).
    #
    # UI-thread-confined.
    #
    # == Implementation details
    #
    # **The grab has four releases and no relinquishing**: the up, the next
    # down (the up was lost — ssh and tmux do lose them), any key, and the
    # terminal losing focus ({#release_grab}). None of the last three tells the
    # grabbed component. Hiding or detaching it does not end the grab either;
    # the router just stops delivering to it until the release
    # (`D_mouse_dispatch`).
    #
    # **The hovered chain is derived, never toggled**: it is the path under the
    # last reported pointer position, or empty while that position is unknown —
    # since the terminal lost focus, or since a key or a paste, after which the
    # pointer may be anywhere, the terminal never reporting it leaving.
    # {#sync_hover} is its sole writer, run after every event and every repaint,
    # so a popup opening over the pointer or a pane scrolling under it moves the
    # hover with no motion at all. While a press is grabbed, hover is suspended:
    # the chain only loses members that were detached, hidden or reparented.
    class Router
      # One step of a resolved path: a component, and the event point in *its*
      # coordinates. The walk down is the only place that conversion is cheap —
      # it already holds the running offset — so it is done there once rather
      # than by each component asking where it is.
      # @api private
      Hit = Data.define(:component, :point)
      private_constant :Hit

      # @param screen [Screen]
      def initialize(screen)
        @screen = screen
        @level = :hover
        @pointer = nil
        @hovered = []
        @grabbed = nil
        @grab_button = nil
      end

      # The tracking level {Screen#run_event_loop} asked the terminal for, one of
      # {Mouse::LEVELS}; `:hover` while no loop is running, so a spec may post
      # anything. An ungrabbed move is dropped below `:hover` — under `:drag` the
      # terminal reports one only while a button nobody claimed is held, and
      # enter/exit that fire *sometimes* are worse than none.
      # @return [Symbol, nil]
      attr_reader :level

      # A new level starts with the pointer unknown: one a previous level
      # reported is no longer being tracked.
      # @param level [Symbol, nil]
      # @return [void]
      def level=(level)
        @level = level
        forget_pointer
      end

      # @return [Component, nil] the component whose {Component#handle_mouse_down?}
      #   claimed the press currently held.
      attr_reader :grabbed

      # @return [Component, nil] the innermost component under the pointer, as of
      #   the last {#sync_hover}; nil below `:hover`.
      def hovered = @hovered.last

      # @param event [Mouse::Event]
      # @return [void]
      def dispatch(event)
        case event
        when DownEvent then press(event)
        when UpEvent then release(event)
        when ScrollEvent
          track(event.point)
          bubble(extent_path(event.point), :handle_mouse_scroll?, event)
        when MoveEvent then move(event)
        when DragEvent
          # No route of its own: it is manufactured here from a move while
          # something holds the grab, so a posted one can only be a mistake.
          raise Tuile::Error,
                "a Mouse::DragEvent is the router's own; post " \
                "Mouse::MoveEvent.new(:#{event.button}, #{event.x}, #{event.y}) " \
                "— or FakeScreen#drag — to drive a grabbed component"
        else raise TypeError, "not a routable Mouse::Event: #{event.inspect}"
        end
      end

      # Ends the grab without telling the grabbed component.
      # @return [void]
      def release_grab
        @grabbed = nil
        @grab_button = nil
      end

      # Marks the pointer's position unknown, so the next {#sync_hover} clears
      # the hover until a report says where it is.
      # @return [void]
      def forget_pointer
        @pointer = nil
      end

      # Brings the hovered chain up to date with the pointer and the tree,
      # firing {Component#handle_mouse_exit} innermost first, then
      # {Component#handle_mouse_enter} root first. Idempotent.
      # @return [void]
      def sync_hover
        chain = if @pointer.nil? then []
                elsif @grabbed.nil? then extent_path(@pointer).map(&:component)
                else
                  @hovered.each_with_index.take_while do |c, i|
                    c.attached? && c.visible? && (i.zero? || c.parent.equal?(@hovered[i - 1]))
                  end.map(&:first)
                end
        rehover(chain) unless chain == @hovered
      end

      private

      # Records where a report put the pointer. Below `:hover` the pointer is
      # left unknown, or a press would light a hover no move ever clears.
      # @param point [Point] in screen coordinates.
      # @return [void]
      def track(point)
        @pointer = point if @level == :hover
      end

      # @param event [DownEvent]
      # @return [void]
      def press(event)
        release_grab
        point = event.point
        track(point)
        pane = @screen.pane
        root = pane.mouse_root_at(point)
        path = rect_path(root, point)
        pane.dismissing_popups_outside(point, left: event.button == :left) do
          focus_innermost(root, path) if event.button == :left
          claimant = bubble(within_extent(path), :handle_mouse_down?, event)
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
        return if grabbed.nil? || !ComponentUtil.effectively_visible?(grabbed)

        local = grabbed.to_local(event.point)
        grabbed.__send__(:handle_mouse_up, event.with(x: local.x, y: local.y))
      end

      # @param event [MoveEvent]
      # @return [void]
      def move(event)
        track(event.point)
        unless @grabbed.nil?
          if ComponentUtil.effectively_visible?(@grabbed)
            local = @grabbed.to_local(event.point)
            @grabbed.__send__(:handle_mouse_drag, DragEvent.new(@grab_button, local.x, local.y))
          end
          return
        end
        return unless @level == :hover

        # Synced here rather than left to the settle, so the enters precede the
        # move they announce.
        sync_hover
        bubble(extent_path(event.point), :handle_mouse_move?, event)
      end

      # A non-modal overlay is never focused into: it sits outside the key scope,
      # so focus there would make every keystroke go dead (`D_overlay`).
      # @param root [Component, nil]
      # @param path [Array<Hit>]
      # @return [void]
      def focus_innermost(root, path)
        return if root.is_a?(Component::Overlay) && !root.modal?

        target = path.reverse_each.map(&:component).find(&:focusable?)
        @screen.focused = target unless target.nil? || target.active?
      end

      # @param path [Array<Hit>] root first.
      # @param handler [Symbol] a routed `handle_mouse_…?`.
      # @param event [Mouse::Event] in screen coordinates; each component is
      #   handed it converted to its own.
      # @return [Component, nil] the component that answered true.
      def bubble(path, handler, event)
        # A handler may detach what is below it on the path (a click that swaps
        # a slot's occupant), so re-check before each delivery.
        hit = path.reverse_each.find do |h|
          h.component.attached? &&
            h.component.__send__(handler, event.with(x: h.point.x, y: h.point.y))
        end
        hit&.component
      end

      # @param point [Point] in screen coordinates.
      # @return [Array<Hit>] the shown components under `point` whose extent
      #   contains it, root first.
      def extent_path(point) = within_extent(rect_path(@screen.pane.mouse_root_at(point), point))

      # @param path [Array<Hit>]
      # @return [Array<Hit>] the prefix whose extent contains the point — the
      #   test each component answers in its own coordinates, so a widget that
      #   paints less than its rect has a dead tail (`D_extent`).
      def within_extent(path) = path.take_while { _1.component.local_extent_rect.contains?(_1.point) }

      # @param root [Component, nil]
      # @param point [Point] in `root`'s parent's coordinates — screen
      #   coordinates, since every mouse root is a {ScreenPane} child.
      # @return [Array<Hit>] the shown components whose rect contains `point`,
      #   root first, each paired with the point in its own coordinates. Tiled
      #   siblings never overlap, so at most one child qualifies at each level.
      def rect_path(root, point)
        path = []
        component = root
        while component&.visible? && component.rect.contains?(point)
          point = Point.new(point.x - component.rect.left, point.y - component.rect.top)
          path << Hit.new(component:, point:)
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
    end
  end
end
