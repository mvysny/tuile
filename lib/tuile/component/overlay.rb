# frozen_string_literal: true

module Tuile
  class Component
    # A component mounted on the {Screen}'s overlay stack rather than in the
    # tiled tree: it floats above the content, and has an open/close lifecycle.
    # It opens with a *placement* — where it wants to be — and the
    # {ScreenPane}'s layout pass turns that into its rect, again on every
    # resize:
    #
    #   overlay = Component::Overlay.new(content: Component::Label.new("saved"))
    #   overlay.open(Overlay::At[Rect.new(10, 4, 20, 1)])   # mounts it on the Screen
    #   overlay.placement = Overlay::At[Rect.new(10, 6, 20, 1)]   # moves it
    #   overlay.close
    #
    # That is the whole of it — floating, plus the lifecycle, {#on_close},
    # outside-click dismissal and {#owner}. {Component::Popup} is the subclass
    # that adds a declared size, centering, focus and key handling.
    #
    # Where it goes is a {Placement}: {At} a fixed rect, {Centered} and
    # {TopRight} an overlay that declares its size ({#declared_size_in}),
    # {ListDropdown::Anchored} a dropdown hanging off a field.
    #
    # The wrapped content fills the overlay's whole {#rect}; for a frame and a
    # caption, wrap a {Component::Window} and let it draw its own border.
    #
    # == Implementation details
    #
    # **{#focusable?} and {#modal?} move together — flip both or neither.** The
    # defaults here are inert (`false`, `false`): a bare overlay floats without
    # disturbing focus or key dispatch. {Component::Popup} flips both. What must
    # not appear is a *focusable non-modal* overlay: {ScreenPane#handle_key?}
    # scopes delivery to the topmost modal popup or else the tiled content, so
    # such an overlay would hold focus outside the key scope, where delivery
    # reaches nobody and *every* keystroke goes dead until Tab recovers. A
    # non-modal overlay is therefore driven from its owner's key handler
    # ({Component::Select} forwarding to its dropdown) instead of claiming focus.
    #
    # **An overlay whose size changes calls {#reposition}**, which asks the pane
    # to place it again; the placement itself stays put. That is how a growing
    # {Component::Notification} or a re-measured {Component::ConfirmWindow}
    # gets its new rect.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class Overlay < Component
      include Component::HasContent

      # Where an overlay wants to be. Include it to *be* a placement — the pane
      # asks for a rect on every layout pass, and an app supplies its own by
      # answering {#rect_for}:
      #
      #   Bottom = Data.define do
      #     include Overlay::Placement
      #
      #     def rect_for(overlay, screen_size, _anchor_rect)
      #       size = overlay.declared_size_in(screen_size)
      #       Rect.new(0, screen_size.height - size.height, size.width, size.height)
      #     end
      #   end
      #
      #   overlay.open(Bottom[])
      #
      # A placement is a **rule, not a rect**: it is re-read on every resize and
      # every settle, so re-running it moves nothing that stood still. Built in
      # are {At}, {Centered}, {TopRight} and {ListDropdown::Anchored}.
      #
      # == Anchors
      #
      # A placement that hangs off something on screen — a field, a menu row —
      # says so by answering {#anchor}; the pane resolves it and hands the rect
      # to {#rect_for}:
      #
      #   def anchor = field
      #
      # Resolving is deliberately the framework's job: a component becomes a
      # screen rect through an ancestor-inclusive visibility walk, an
      # {Component#attached?} test and {Component#absolute_extent_rect} (not
      # {Component#absolute_rect}) — three invariants, one of them the trap
      # {Component#walk_shown_tree} exists to prevent. {#anchor} therefore
      # answers one of three things:
      #
      # - a {Component} — resolved while it is reachable, and **losable**: once
      #   detached or hidden there is no rect to compute, so the pane leaves the
      #   overlay where it was and warns its owner once rather than placing it
      #   against nothing. Closing it is the owner's job.
      # - a {Rect} in screen coordinates — always resolves, never lost. Anchors to an absolute position.
      # - `nil`, the default — not anchored; {#rect_for} is handed `nil`.
      #
      # An anchor also earns a **second settle pass**: the pane lays out before
      # the content its anchor sits in does, so {Screen#flush_layout} re-reads
      # every {#anchor} once the queue is empty and runs the pane again if any
      # now resolves elsewhere.
      module Placement
        # What this placement hangs off, re-read on every pass — see the
        # *Anchors* section above.
        # @return [Component, Rect, nil] `nil`, the default, is not anchored.
        def anchor = nil

        # The rect this placement wants for `overlay`, in screen coordinates.
        # The pane assigns it as-is — clamping it on screen is the placement's
        # own job.
        # @param overlay [Overlay] the overlay being placed.
        # @param screen_size [Size] the whole terminal.
        # @param anchor_rect [Rect, nil] {#anchor} resolved to screen
        #   coordinates; `nil` only for an unanchored placement, since a lost
        #   anchor is not placed at all.
        # @raise [NotImplementedError] unless the includer overrides it.
        # @return [Rect]
        def rect_for(overlay, screen_size, anchor_rect)
          raise(NotImplementedError, "#{self.class}#rect_for")
        end
      end

      # Places the overlay at exactly `rect`, in screen coordinates.
      #
      #   overlay.open(Overlay::At[Rect.new(10, 4, 20, 1)])
      #
      # @!attribute [r] rect
      #   @return [Rect]
      At = Data.define(:rect) do
        include Placement

        # @param _overlay [Overlay]
        # @param _screen_size [Size]
        # @param _anchor_rect [Rect, nil] unused: this placement declares no {#anchor}.
        # @return [Rect]
        def rect_for(_overlay, _screen_size, _anchor_rect) = rect
      end

      # Centers the overlay on the screen at the size it declares
      # ({Overlay#declared_size_in}) — {Popup}'s default.
      Centered = Data.define do
        include Placement

        # @param overlay [Overlay]
        # @param screen_size [Size]
        # @param _anchor_rect [Rect, nil] unused: this placement declares no {#anchor}.
        # @return [Rect]
        def rect_for(overlay, screen_size, _anchor_rect)
          size = overlay.declared_size_in(screen_size)
          Rect.new(0, 0, size.width, size.height).centered(screen_size)
        end
      end

      # Puts the overlay in the screen's top-right corner at the size it
      # declares ({Overlay#declared_size_in}) — {Notification}'s default.
      TopRight = Data.define do
        include Placement

        # @param overlay [Overlay]
        # @param screen_size [Size]
        # @param _anchor_rect [Rect, nil] unused: this placement declares no {#anchor}.
        # @return [Rect]
        def rect_for(overlay, screen_size, _anchor_rect)
          size = overlay.declared_size_in(screen_size)
          Rect.new([screen_size.width - size.width, 0].max, 0, size.width, size.height)
        end
      end

      # @param content [Component, nil] initial content; can be set later via
      #   {#content=}. It fills the overlay's {#rect} and does not determine it.
      # @param close_on_outside_click [Boolean] true (default) to dismiss on a
      #   left click that misses this overlay. See {#close_on_outside_click?}.
      def initialize(content: nil, close_on_outside_click: true)
        super()
        @close_on_outside_click = close_on_outside_click
        @owner = nil
        @content = nil
        self.content = content unless content.nil?
      end

      # @return [Boolean] false — a bare overlay scopes no keys and blocks no
      #   clicks. {Component::Popup} overrides it, together with {#focusable?}.
      def modal? = false

      # @return [Boolean] false — a bare overlay leaves focus where it was. See
      #   the class docs: override it only together with {#modal?}.
      def focusable? = false

      # @return [Boolean] false — Tab never lands on the overlay wrapper itself
      #   (its content may still carry stops).
      def tab_stop? = false

      # Refused: an overlay is **dismissed, not hidden**. Use {#close} and
      # {#open} — which already keep it alive between showings, the one thing
      # hiding would buy — or hide the *content* if only a piece of it comes
      # and goes.
      #
      # The pane resolves clicks and key scope from its popup list, which does
      # not consult this flag, so a hidden overlay would paint nothing while
      # still swallowing every click and, if modal, scoping every key: the
      # invisible-modal trap the class docs warn about for {#focusable?} and
      # {#modal?}.
      # @param _value [Boolean]
      # @raise [Tuile::Error] always.
      # @return [void]
      def visible=(_value)
        raise Tuile::Error, "#{self.class} cannot be hidden — close it instead (Overlay#close)"
      end

      # Whether a left click outside this overlay closes it (default true). The
      # pane does the closing — {ScreenPane#dismissing_popups_outside} snapshots
      # the open overlays *before* the press is routed and closes the
      # dismissable ones *after*, so a widget that toggles its own overlay from a click on its
      # face (a {Component::Select}, a {Component::MenuBar} title) still toggles
      # correctly: the delivered click closes the overlay and the dismissal then
      # no-ops on it, rather than closing and reopening it. Only `:left`
      # dismisses; scroll and right clicks never do.
      #
      # **"Outside" spans the {#owner} chain, not just this rect.** A click
      # counts as inside this overlay when it lands in its rect *or* in any
      # overlay that belongs to it — so a dialog is not dismissed by a click on a
      # dropdown its own field opened, and a menu cascade is not dismissed by a
      # click on one of its deeper panels. Overlays with no owner relationship
      # are independent: clicking one dismisses the other, which is what a
      # window-like overlay should do. One that must survive unrelated clicks
      # entirely ({Component::Notification}) sets this false.
      #
      # Every dismissable overlay closes, not just the topmost, and stacking
      # order plays no part: a {Component::MenuBar} cascade must vanish whole on
      # one click on the background, not peel one panel per click.
      # @return [Boolean]
      def close_on_outside_click? = @close_on_outside_click

      # @return [Boolean] see {#close_on_outside_click?}.
      attr_writer :close_on_outside_click

      # The component this overlay is *part of*, or `nil` (the default) when it
      # is an overlay in its own right. It exists for outside-click dismissal: a
      # click inside this overlay also counts as inside whatever overlay encloses
      # its owner, so the host is not dismissed by a click on a panel it put
      # there. See {#close_on_outside_click?}.
      #
      # Set it to the *driver* — {Component::ComboBox} hands its dropdown `self`
      # — rather than to the enclosing overlay: the driver knows what it is,
      # while the overlay above it is a tree relationship the pane resolves at
      # click time (so it cannot go stale). Any {Component} is accepted, and an
      # `Overlay` resolves to itself, which is how a
      # {Component::MenuBar::Cascade} chains each panel to the one it dropped out
      # of.
      # @return [Component, nil]
      attr_accessor :owner

      # What {#on_close} fires.
      #
      # @!attribute [r] source
      #   @return [Overlay] the overlay that left the screen.
      CloseEvent = Data.define(:source) { include Tuile::Event }

      # @!method on_close
      #   Fired with a {CloseEvent} once this overlay has left the screen —
      #   **however it left**: {#close}, a direct {Screen#remove_popup}, an
      #   outside click, or teardown via {Screen#close}. That unconditionality is
      #   the point, so it hangs off {#handle_detached} rather than {#close}; a
      #   driver keeping its own record of open overlays reconciles it here and
      #   cannot drift ({Component::MenuBar::Cascade} is the worked example).
      #
      #   It fires *after* the overlay is detached, so {#open?} is already false
      #   and the usual {Component#handle_detached} caveats apply: release state,
      #   don't inspect the tree, keep it trivial (it may run while the pane is
      #   mid-way through closing a batch of overlays, and a raise propagates).
      #   @return [Listeners]
      listener :on_close

      # The box this overlay asks for on a screen of `screen_size` — what
      # {Centered} and {TopRight} place. A bare overlay declares none.
      # @param _screen_size [Size]
      # @raise [Tuile::Error] always, here; {Popup} and {Notification} answer.
      # @return [Size]
      def declared_size_in(_screen_size)
        raise Tuile::Error, "#{self.class} declares no size — place it with Overlay::At[rect]"
      end

      # The placement a bare {#open} uses. A bare overlay has none, because
      # nothing about it says where it goes.
      # @raise [ArgumentError] always, here; {Popup} and {Notification} answer.
      # @return [Placement]
      def default_placement
        raise ArgumentError, "#{self.class} has no default placement — open(Overlay::At[rect])"
      end

      # Escalates to a full scene repaint when an open overlay shrinks or moves
      # so its new rect no longer covers the cells it previously painted. An
      # overlay overdraws the scene without clipping and nothing clears
      # underneath it, so {Screen#repaint}'s overlay-only fast path would repaint
      # into the new rect and leave the vacated cells showing stale content.
      # When the new rect fully covers the old one (the overlay only grew), the
      # fast path is correct and the full repaint is skipped.
      # @param old_rect [Rect]
      # @return [void]
      def handle_rect_changed(old_rect)
        super
        screen.needs_full_repaint if open? && !rect.contains_rect?(old_rect)
      end

      # Mounts this overlay on the {Screen} at `placement`; the pane assigns the
      # rect on the next settle.
      #
      #   Component::Popup.new(content: window).open   # its default: centered
      #   overlay.open(Overlay::At[Rect.new(10, 4, 20, 1)])
      #
      # There is deliberately no class-level `Overlay.open` factory — see
      # `design/decisions.md` `D_popup_open`; returning `self` is what keeps the
      # one-liner above available without one.
      # @param placement [Placement] where it wants to be.
      # @raise [ArgumentError] with no placement, for an overlay that has no
      #   {#default_placement}.
      # @raise [TypeError] if `placement` does not include {Placement}.
      # @return [self]
      def open(placement = default_placement)
        screen.add_popup(self, placement)
        self
      end

      # Removes this overlay from the {Screen}. No-op if not currently open.
      # @return [void]
      def close
        screen.remove_popup(self)
      end

      # @return [Boolean] true if this overlay is currently mounted on the screen.
      def open?
        screen.has_popup?(self)
      end

      # Where this overlay wants to be, or `nil` while closed.
      # @return [Placement, nil] the placement it was opened or moved with.
      def placement = open? ? screen.pane.placement(self) : nil

      # Moves the open overlay; it takes the new rect on the next settle.
      # @param placement [Placement] see the class docs.
      # @raise [Tuile::Error] unless open — a closed overlay takes its
      #   placement from {#open}.
      # @raise [TypeError] if `placement` does not include {Placement}.
      # @return [void]
      def placement=(placement)
        raise Tuile::Error, "#{self} is not open — pass the placement to #open" unless open?

        screen.pane.constrain(self, placement)
      end

      # Asks the pane to place this overlay again, because something its
      # placement reads — its declared size, its row count — changed. A no-op
      # while closed: {#open} places it anyway.
      # @return [void]
      def reposition
        parent&.invalidate_layout
      end

      # Fires {#on_close}. A subclass overriding this **must** call `super`, or
      # the overlay's driver never hears that it closed.
      # @return [void]
      def handle_detached
        super
        on_close.fire(CloseEvent.new(source: self))
      end

      protected

      # Content fills the overlay's full rect — an Overlay has no border to
      # subtract.
      # @return [void]
      def relayout
        content&.rect = local_rect
      end
    end
  end
end
