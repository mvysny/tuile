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
      def initialize(content: nil, modal: true, size: Fraction::HALF)
        super()
        @modal = modal
        @size = size
        @content = nil
        self.content = content unless content.nil?
        reposition
      end

      # @return [Size, Fraction] the popup's declared size. See {#size=}.
      attr_reader :size

      # @return [Boolean] whether this popup is modal. See {#initialize}.
      def modal? = @modal

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
      # @return [void]
      def open
        reposition
        screen.add_popup(self)
      end

      # Constructs and opens a popup in one call.
      # @param content [Component, nil]
      # @param modal [Boolean] see {#initialize}.
      # @param size [Size, Fraction] see {#initialize}.
      # @return [Popup] the opened popup.
      def self.open(content: nil, modal: true, size: Fraction::HALF)
        Popup.new(content: content, modal: modal, size: size).tap(&:open)
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
