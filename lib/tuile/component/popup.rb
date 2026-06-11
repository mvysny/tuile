# frozen_string_literal: true

module Tuile
  class Component
    # An overlay that wraps any {Component} as its content. Popup itself
    # paints nothing — it's a transparent host that handles its lifecycle
    # ({#open} / {#close} / {#open?}, ESC/q to close) and auto-sizes to the
    # wrapped content.
    #
    # Modal by default: it centers on the screen, grabs focus, eats keys, and
    # blocks clicks beneath it. Pass `modal: false` for a non-modal overlay
    # that floats above the content (still painted on top, still auto-sized)
    # without taking focus or capturing input — the caller positions it (via
    # {#rect=}) and drives it from app code. That is the building block for an
    # autocomplete/slash-command list anchored to a {Component::TextField} or
    # {Component::TextArea} caret: typing keeps focus (and the cursor) in the
    # input, an {Component::TextInput#on_change} listener refills the list, and
    # an {Component::TextInput#on_key} interceptor forwards Up/Down/Enter to it.
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
    # `q` and ESC close the popup. Any nested {Component::TextField} that owns
    # the hardware cursor swallows printable keys first via the standard
    # cursor-owner suppression in {Component#handle_key}, so typing `q` into a
    # text field doesn't dismiss the popup.
    class Popup < Component
      include Component::HasContent

      # @param content [Component, nil] initial content; can be set later via
      #   {#content=}. When provided here, the popup auto-sizes to fit.
      # @param modal [Boolean] true (default) for a centered, focus-grabbing,
      #   input-capturing modal; false for a non-modal overlay the caller
      #   positions and drives (see the class docs).
      def initialize(content: nil, modal: true)
        super()
        @modal = modal
        @content = nil
        self.content = content unless content.nil?
      end

      # @return [Boolean] whether this popup is modal. See {#initialize}.
      def modal? = @modal

      def focusable? = true

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

      # Mounts this popup on the {Screen}. Recomputes the popup's size from
      # the current content first, so reopening a popup whose content has
      # grown or shrunk while closed picks up the new size.
      # @return [void]
      def open
        update_rect unless @content.nil?
        screen.add_popup(self)
      end

      # Constructs and opens a popup in one call.
      # @param content [Component, nil]
      # @return [Popup] the opened popup.
      def self.open(content: nil)
        Popup.new(content: content).tap(&:open)
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

      # Recenters the popup on the screen, preserving its current width/height.
      # Called automatically by the screen's layout pass and by {#content=}
      # when the popup is open.
      # @return [void]
      def center
        self.rect = rect.centered(screen.size)
      end

      # @return [Integer] max height the popup will grow to fit its content.
      #   Defers to the content's {Component#popup_max_height} advice when it
      #   gives one, else defaults to 12. Override in a subclass to allow
      #   taller popups regardless of content.
      def max_height = @content&.popup_max_height || 12

      # @return [Integer] min height the popup occupies even when its content
      #   is shorter. Defers to the content's {Component#popup_min_height}
      #   advice when it gives one, else defaults to 0 (size purely to
      #   content) — so a {Component::LogWindow} stays readable while only a
      #   few lines are in without callers wiring up a subclass. Override in a
      #   subclass to keep any popup from collapsing to a couple of rows.
      #   Capped at the same 4/5-of-screen ceiling {#update_rect} applies.
      def min_height = @content&.popup_min_height || 0

      # Sets the popup's content and auto-sizes the popup to fit.
      # @param new_content [Component, nil]
      def content=(new_content)
        super
        update_rect unless new_content.nil?
      end

      # Re-sizes (and recenters, when open) whenever the wrapped content's
      # natural size changes — e.g. a {Label}'s `text=`, a {List}'s
      # `add_line`, or a nested {Window} whose own content grew (the window
      # recomputes its {Component#content_size} and the change bubbles here).
      # @param _child [Component]
      # @return [void]
      def on_child_content_size_changed(_child)
        update_rect
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

      private

      # Recompute width/height from {#content}'s natural size and recenter
      # if currently open. Called whenever content is (re)assigned.
      #
      # Computes the final (centered) rect and assigns it in one step rather
      # than positioning at the origin and then centering: the intermediate
      # origin rect rarely covers the previous one, which would make
      # {#rect=}'s shrink/move detection fire a full repaint on every resize.
      # @return [void]
      def update_rect
        ceiling = screen.size.height * 4 / 5
        size = @content.content_size.clamp_height(max_height)
        size = size.clamp(Size.new(screen.size.width * 4 / 5, ceiling))
        floor = min_height.clamp(0, ceiling)
        size = Size.new(size.width, floor) if size.height < floor
        # A non-modal overlay is positioned by the caller, so an open one keeps
        # its current top-left when its content resizes; a modal popup recenters.
        origin = open? && !modal? ? Point.new(rect.left, rect.top) : Point.new(0, 0)
        r = Rect.new(origin.x, origin.y, size.width, size.height)
        r = r.centered(screen.size) if open? && modal?
        self.rect = r
      end
    end
  end
end
