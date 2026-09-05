# frozen_string_literal: true

module Tuile
  class Component
    # A component mounted on the {Screen}'s overlay stack rather than in the
    # tiled tree: it floats above the content at a rect the caller assigns, and
    # has an open/close lifecycle instead of a parent that lays it out.
    #
    #   overlay = Component::Overlay.new(content: Component::Label.new("saved"))
    #   overlay.rect = Rect.new(10, 4, 20, 1)   # you place it — nothing else does
    #   overlay.open                            # mounts it on the Screen
    #   overlay.close
    #
    # That is the whole of it — floating, plus the lifecycle, {#on_close},
    # outside-click dismissal and {#owner}. {Component::Popup} is the subclass
    # that adds a declared size, self-centering, focus and key handling.
    #
    # The wrapped content fills the overlay's whole {#rect}; for a frame and a
    # caption, wrap a {Component::Window} and let it draw its own border.
    #
    # == Implementation details
    #
    # **{#focusable?} and {#modal?} move together — flip both or neither.** The
    # defaults here are inert (`false`, `false`): a bare overlay floats without
    # disturbing focus or key dispatch. {Component::Popup} flips both. What must
    # not appear is a *focusable non-modal* overlay: {ScreenPane#handle_key}
    # scopes delivery to the topmost modal popup or else the tiled content, so
    # such an overlay would hold focus outside the key scope, where delivery
    # reaches nobody and *every* keystroke goes dead until Tab recovers. A
    # non-modal overlay is therefore driven from its owner's key handler
    # ({Component::Select} forwarding to its dropdown) instead of claiming focus.
    #
    # **A derived position needs a {#reposition} override.** The default is a
    # no-op: the rect is whatever the caller last assigned. An overlay whose
    # position is computed — from the screen, or from an anchor — must recompute
    # it there, or it keeps a stale rect after a SIGWINCH and sits off-screen
    # entirely if the terminal narrowed. Closing on resize is equally legal
    # ({Component::MenuBar} drops its cascade from `rect=` rather than walking
    # every level to re-anchor it).
    #
    # UI-thread-confined, like every component (see {Screen}).
    class Overlay < Component
      include Component::HasContent

      # @param content [Component, nil] initial content; can be set later via
      #   {#content=}. It fills the overlay's {#rect} and does not determine it.
      # @param close_on_outside_click [Boolean] true (default) to dismiss on a
      #   left click that misses this overlay. See {#close_on_outside_click?}.
      def initialize(content: nil, close_on_outside_click: true)
        super()
        @close_on_outside_click = close_on_outside_click
        @owner = nil
        @on_close = nil
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
      # pane does the closing — {ScreenPane#handle_mouse} snapshots the open
      # overlays *before* routing the click and closes the dismissable ones
      # *after*, so a widget that toggles its own overlay from a click on its
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

      # A callback taking no arguments, fired once this overlay has left the
      # screen — **however it left**: {#close}, a direct {Screen#remove_popup},
      # an outside click, or teardown via {Screen#close}. That unconditionality
      # is the point, so it hangs off {#on_detached} rather than {#close}; a
      # driver keeping its own record of open overlays reconciles it here and
      # cannot drift ({Component::MenuBar::Cascade} is the worked example).
      #
      # It fires *after* the overlay is detached, so {#open?} is already false
      # and the usual {Component#on_detached} caveats apply: release state, don't
      # inspect the tree, keep it trivial (it may run while the pane is mid-way
      # through closing a batch of overlays, and a raise propagates).
      # @return [Proc, nil]
      attr_accessor :on_close

      # Reassigns the overlay's rect, escalating to a full scene repaint when an
      # open overlay shrinks or moves so its new rect no longer covers the cells
      # it previously painted. An overlay overdraws the scene without clipping
      # and nothing clears underneath it, so {Screen#repaint}'s overlay-only fast
      # path would repaint into the new rect and leave the vacated cells showing
      # stale content. When the new rect fully covers the old one (the overlay
      # only grew), the fast path is correct and the full repaint is skipped.
      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        old_rect = rect
        super
        screen.needs_full_repaint if open? && !new_rect.contains_rect?(old_rect)
      end

      # Mounts this overlay on the {Screen}.
      #
      #   overlay = Component::Overlay.new(content: label).open   # construct and mount
      #
      # There is deliberately no class-level `Overlay.open` factory — see
      # `DECISIONS.md` `D_popup_open`; returning `self` is what keeps the
      # one-liner above available without one.
      # @return [self]
      def open
        reposition
        screen.add_popup(self)
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

      # Recomputes this overlay's own rect (not its content's layout). A no-op
      # here — the rect is whatever the caller assigned — and the hook a subclass
      # with a *derived* position overrides; see the class docs. Called on
      # {#open} and by the screen's layout pass, so an override tracks SIGWINCH.
      # @return [void]
      def reposition; end

      # Fires {#on_close}. A subclass overriding this **must** call `super`, or
      # the overlay's driver never hears that it closed.
      # @return [void]
      def on_detached
        @on_close&.call
      end

      protected

      # Content fills the overlay's full rect — an Overlay has no border to
      # subtract.
      # @param content [Component]
      # @return [void]
      def layout(content)
        content.rect = rect
      end
    end
  end
end
