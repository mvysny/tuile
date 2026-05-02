# frozen_string_literal: true

module Tuile
  class Component
    # A modal overlay that wraps any {Component} as its content. Popup itself
    # paints nothing — it's a transparent host that handles modality
    # ({#open} / {#close} / {#open?}, ESC/q to close), centers itself on the
    # screen, and auto-sizes to the wrapped content.
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
      def initialize(content: nil)
        super()
        @content = nil
        # Off-screen sentinel until the content sets a real size and the popup
        # is centered on open.
        @rect = Rect.new(-1, -1, 0, 0)
        self.content = content unless content.nil?
      end

      def focusable? = true

      # Mounts this popup on the {Screen}.
      # @return [void]
      def open
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
        self.rect = rect.centered(screen.size.width, screen.size.height)
      end

      # @return [Integer] max height the popup will grow to fit its content,
      #   defaults to 12. Override in a subclass to allow taller popups.
      def max_height = 12

      # Sets the popup's content and auto-sizes the popup to fit.
      # @param new_content [Component, nil]
      def content=(new_content)
        super
        update_rect unless new_content.nil?
      end

      # Hint for the status bar: own "q Close" plus the wrapped content's hint.
      # @return [String]
      def keyboard_hint
        prefix = "q #{Rainbow("Close").cadetblue}"
        child_hint = @content&.keyboard_hint.to_s
        child_hint.empty? ? prefix : "#{prefix}  #{child_hint}"
      end

      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_key(key)
        return true if super

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
      # @return [void]
      def update_rect
        size = @content.content_size.clamp_height(max_height)
        size = size.clamp(screen.size.width * 4 / 5, screen.size.height * 4 / 5)
        self.rect = Rect.new(-1, -1, size.width, size.height)
        center if open?
      end
    end
  end
end
