# frozen_string_literal: true

module Tuile
  class Component
    # A modal dialog: an {Component::Overlay} centered on the screen, which
    # grabs focus, scopes keys to its own subtree, blocks clicks beneath it, and
    # closes on ESC or `q`.
    #
    #   window = Component::Window.new("Help")
    #   window.content = Component::List.new.tap { _1.lines = lines }
    #   Component::Popup.new(content: window).open
    #
    # Bare content also works (a {Component::Label}, a {Component::List}…), in
    # which case the popup is borderless. For a floating layer that does *not*
    # take focus or capture input — an autocomplete list anchored to a field, a
    # toast — use {Component::Overlay} directly.
    #
    # The popup does *not* size itself to its content. Its box is set by
    # {#declared_size} — a {Fraction} (resolved against the screen every layout
    # pass, so it tracks resize) or an absolute {Size} (clamped to the screen).
    # The default is {Fraction::HALF}: half the screen, centered. The wrapped content
    # then fills that box and handles its own overflow by wrapping and scrolling,
    # so use content that can — a {Component::TextView} or
    # {Component::TextArea} — for anything longer than fits. A
    # {Component::Label} only truncates.
    #
    # == Implementation details
    #
    # `q` and ESC close the popup — handled here, at the top of the popup's own
    # subtree, so the key only arrives after every component on the focus chain
    # declined it (see {ScreenPane#handle_key?}). That's why typing `q` into a
    # nested {Component::TextField} doesn't dismiss the popup: the field consumes
    # it first.
    #
    # A left click *outside* the popup closes it too — see
    # {Overlay#close_on_outside_click?} for the exact contract and
    # {Overlay#on_close} for the notice a driver hears when it happens.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class Popup < Overlay
      # @param content [Component, nil] initial content; can be set later via
      #   {#content=}. The content fills the popup's {#rect}; it does not
      #   determine the popup's size.
      # @param declared_size [Size, Fraction] the popup's box, applied top-down.
      #   A {Fraction} is resolved against the screen each layout pass; a {Size}
      #   is clamped to the screen. Defaults to {Fraction::HALF}.
      # @param close_on_outside_click [Boolean] true (default) to dismiss on a
      #   left click that misses this popup. See
      #   {Overlay#close_on_outside_click?}.
      def initialize(content: nil, declared_size: Fraction::HALF, close_on_outside_click: true)
        super(content: content, close_on_outside_click: close_on_outside_click)
        @declared_size = declared_size
      end

      # The box this popup asks for, *as set* — a {Fraction} comes back
      # unresolved. {#rect} is the resolved answer. Named apart from `size`
      # because a component's `size` is its `rect.size`, which this is not: it
      # is an input re-read on every layout pass, not a report of the current
      # geometry.
      # @return [Size, Fraction] see {#declared_size=}.
      attr_reader :declared_size

      # @return [Boolean] true — a Popup scopes key dispatch, grabs focus on
      #   open, and blocks clicks on the content beneath it.
      def modal? = true

      # @return [Boolean] true — {ScreenPane#add_popup} focuses a popup on open,
      #   and focus repair falls back to it when its subtree has no tab stop.
      def focusable? = true

      # Sets the popup's box; an open popup takes it on the next settle. Accepts a {Fraction} (resolved
      # against the screen every layout pass, so it tracks resize) or an
      # absolute {Size} (clamped to the screen). This is **authoritative**, not
      # a preference: the screen applies exactly what you ask for (clamped),
      # with no negotiation — a popup has no siblings to compete with.
      # @param new_size [Size, Fraction]
      # @return [void]
      def declared_size=(new_size)
        @declared_size = new_size
        reposition
      end

      # {#declared_size} resolved against `screen_size`: a {Fraction} scaled, a
      # {Size} clamped.
      # @param screen_size [Size]
      # @return [Size]
      def declared_size_in(screen_size)
        @declared_size.is_a?(Fraction) ? @declared_size.resolve(screen_size) : @declared_size.clamp(screen_size)
      end

      # @return [Overlay::Centered] a popup opens centered.
      def default_placement = Centered[]

      # `q` and ESC close the popup. The popup sits on the focus chain of
      # whatever it wraps, so the key reaches here by bubbling up from the
      # focused content after that content declined to handle it.
      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_key?(key)
        if [Keys::ESC, "q"].include?(key)
          close
          true
        else
          false
        end
      end
    end
  end
end
