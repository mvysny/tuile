# frozen_string_literal: true

module Tuile
  class Component
    # An overlay that wraps any {Component} as its content. Popup itself
    # paints nothing — it's a transparent host that handles its lifecycle
    # ({#open} / {#close} / {#open?}, ESC/q to close) and holds a top-down
    # {#size} the {Screen} applies.
    #
    # The popup does *not* size itself to its content. Its box is declared by
    # {#size} — a {Fraction} (resolved against the screen every layout pass, so
    # it tracks resize) or an absolute {Size} (clamped to the screen). The
    # default is {Fraction::HALF}: half the screen, centered. The wrapped
    # content then fills that box and handles its own overflow by wrapping and
    # scrolling, so use content that can — a {Component::TextView} or
    # {Component::TextArea} — for anything longer than fits. A
    # {Component::Label} only truncates.
    #
    # Modal by default: it centers on the screen, grabs focus, eats keys, and
    # blocks clicks beneath it. Pass `modal: false` for a non-modal overlay
    # that floats above the content without taking focus or capturing input —
    # the caller positions it (via {#rect=}), sizes it, and drives it from app
    # code. That's the building block for an autocomplete/slash-command list
    # anchored to a text field's caret: typing keeps focus in the input while
    # the caller refills and drives the overlay.
    #
    # The wrapped content fills the popup's full {#rect}; if you want a frame
    # and caption, wrap a {Component::Window} (or any subclass — including
    # {Component::LogWindow}) and let it draw its own border:
    #
    #   window = Component::Window.new("Help")
    #   window.content = Component::List.new.tap { _1.lines = lines }
    #   Component::Popup.new(content: window).open
    #
    # Bare content also works (a {Component::Label}, a {Component::List}…), in
    # which case the popup is borderless.
    #
    # `q` and ESC close the popup — handled here, at the top of the popup's own
    # subtree, so the key only arrives after every component on the focus chain
    # declined it (see {ScreenPane#handle_key}). That's why typing `q` into a
    # nested {Component::TextField} doesn't dismiss the popup: the field
    # consumes it first.
    #
    # A left click *outside* the popup closes it too, modal or not — see
    # {#close_on_outside_click?} for the exact contract and {#on_close=} for
    # the notice a driver hears when it happens.
    class Popup < Component
      include Component::HasContent

      # @param content [Component, nil] initial content; can be set later via
      #   {#content=}. The content fills the popup's {#rect}; it does not
      #   determine the popup's size.
      # @param modal [Boolean] true (default) for a centered, focus-grabbing,
      #   input-capturing modal; false for a non-modal overlay the caller
      #   positions and drives (see the class docs).
      # @param size [Size, Fraction] the popup's size, applied top-down. A
      #   {Fraction} is resolved against the screen each layout pass; a {Size}
      #   is clamped to the screen. Defaults to {Fraction::HALF}.
      # @param close_on_outside_click [Boolean] true (default) to dismiss on a
      #   left click that misses this popup. See {#close_on_outside_click?}.
      def initialize(content: nil, modal: true, size: Fraction::HALF,
                     close_on_outside_click: true)
        super()
        @modal = modal
        @size = size
        @close_on_outside_click = close_on_outside_click
        @on_close = nil
        @content = nil
        self.content = content unless content.nil?
        reposition
      end

      # @return [Size, Fraction] the popup's declared size. See {#size=}.
      attr_reader :size

      # @return [Boolean] whether this popup is modal. See {#initialize}.
      def modal? = @modal

      # Whether a left click that misses this popup closes it (default true,
      # modal or not). The pane does the closing —
      # {ScreenPane#handle_mouse} snapshots the open popups *before* routing
      # the click and closes the opted-in misses *after*, so a widget that
      # toggles its own overlay from a click on its face (a
      # {Component::Select}, a {Component::MenuBar} title) still toggles
      # correctly: the delivered click closes the overlay and the dismissal
      # then no-ops on it, rather than closing and reopening it. Only
      # `:left` dismisses; scroll and right clicks never do.
      #
      # Every miss closes, not just the topmost — a {Component::MenuBar}
      # cascade must vanish whole on one click, not peel one panel per click.
      # A popup that wants to survive unrelated clicks
      # ({Component::Notification}) sets this false.
      #
      # The flag says "outside *me*" and nothing else: a driver owning several
      # popups hears one {#on_close} per popup and reconciles its own
      # bookkeeping ({Component::MenuBar::Cascade} is the worked example).
      # @return [Boolean]
      def close_on_outside_click? = @close_on_outside_click

      # @return [Boolean] see {#close_on_outside_click?}.
      attr_writer :close_on_outside_click

      # A callback taking no arguments, fired once this popup has left the
      # screen — **however it left**: {#close}, a direct {Screen#remove_popup},
      # an outside click, or teardown via {Screen#close}. That unconditionality
      # is the point, so it hangs off {#on_detached} rather than {#close}; a
      # driver keeping its own record of open popups reconciles it here and
      # cannot drift ({Component::MenuBar::Cascade} is the worked example).
      #
      # It fires *after* the popup is detached, so {#open?} is already false and
      # the usual {Component#on_detached} caveats apply: release state, don't
      # inspect the tree, keep it trivial (it may run while the pane is mid-way
      # through closing a batch of popups, and a raise propagates).
      # @return [Proc, nil]
      attr_accessor :on_close

      def focusable? = true

      # Sets the popup's size and repositions it. Accepts a {Fraction}
      # (resolved against the screen every layout pass, so it tracks resize) or
      # an absolute {Size} (clamped to the screen). This is **authoritative**,
      # not a preference: the screen applies exactly what you ask for (clamped),
      # with no negotiation — a popup has no siblings to compete with.
      # @param new_size [Size, Fraction]
      # @return [void]
      def size=(new_size)
        @size = new_size
        reposition
      end

      # Reassigns the popup's rect, escalating to a full scene repaint when an
      # open popup shrinks or moves so its new rect no longer covers the cells
      # it previously painted. A popup overdraws the scene without clipping and
      # nothing clears underneath it, so {Screen#repaint}'s popup-only fast path
      # would repaint into the new rect and leave the vacated cells showing
      # stale content. When the new rect fully covers the old one (the popup
      # only grew), the fast path is correct and the full repaint is skipped.
      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        old_rect = rect
        super
        screen.needs_full_repaint if open? && !new_rect.contains_rect?(old_rect)
      end

      # Mounts this popup on the {Screen}, re-resolving its {#size} against the
      # current screen first.
      #
      #   popup = Component::Popup.new(content: window).open   # construct and mount
      #
      # There is deliberately no class-level `Popup.open` factory — see
      # `DECISIONS.md` `D-popup-open`; returning `self` is what keeps the
      # one-liner above available without one.
      # @return [self]
      def open
        reposition
        screen.add_popup(self)
        self
      end

      # Removes this popup from the {Screen}. No-op if not currently open.
      # @return [void]
      def close
        screen.remove_popup(self)
      end

      # @return [Boolean] true if this popup is currently mounted on the screen.
      def open?
        screen.has_popup?(self)
      end

      # Re-resolves {#size} against the current screen and repositions the popup
      # *itself* (this is not laying out content — the popup's own rect): a
      # modal popup recenters; a non-modal overlay keeps its caller-assigned
      # top-left (only its size follows the screen). Called on {#open}, on
      # {#size=}, and by the screen's layout pass (so a {Fraction} size tracks
      # SIGWINCH).
      #
      # The final rect is computed and assigned in one step rather than sizing
      # at the origin and then centering: the intermediate origin rect rarely
      # covers the previous one, which would make {#rect=}'s shrink/move
      # detection fire a full repaint on every resize.
      # @return [void]
      def reposition
        size = @size.is_a?(Fraction) ? @size.resolve(screen.size) : @size.clamp(screen.size)
        r = Rect.new(rect.left, rect.top, size.width, size.height)
        r = r.centered(screen.size) if modal?
        self.rect = r
      end

      # Recenters the popup on the screen, preserving its current width/height.
      # @return [void]
      def center
        self.rect = rect.centered(screen.size)
      end

      # Hint for the status bar: own "q Close" plus the wrapped content's hint.
      # @return [String]
      def keyboard_hint
        prefix = "q #{screen.theme.hint("Close")}"
        child_hint = @content&.keyboard_hint.to_s
        child_hint.empty? ? prefix : "#{prefix}  #{child_hint}"
      end

      # `q` and ESC close the popup. The popup sits on the focus chain of
      # whatever it wraps, so the key reaches here by bubbling up from the
      # focused content after that content declined to handle it.
      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_key(key)
        if [Keys::ESC, "q"].include?(key)
          close
          true
        else
          false
        end
      end

      # Fires {#on_close}. A subclass overriding this **must** call `super`, or
      # the popup's driver never hears that it closed.
      # @return [void]
      def on_detached
        @on_close&.call
      end

      protected

      # Content fills the popup's full rect — Popup has no border to subtract.
      # @param content [Component]
      # @return [void]
      def layout(content)
        content.rect = rect
      end
    end
  end
end
