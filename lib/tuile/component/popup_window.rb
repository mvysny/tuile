# frozen_string_literal: true

module Tuile
  class Component
    # A popup window. Adds {#open} which opens the window; the window closes
    # automatically when 'q' or ESC is pressed.
    #
    # The window also sets its size automatically, based on the contents set,
    # by querying {Component#content_size}. {#max_height} is consulted. Any
    # component type works; for {Component::List} content the cursor is also
    # enabled automatically when the list overflows {#max_height}.
    class PopupWindow < Window
      # Opens the popup window.
      # @return [void]
      def open
        screen.add_popup(self)
      end

      # Removes the window from the screen.
      # @return [void]
      def close
        screen.remove_popup(self)
      end

      # @return [Boolean] true if this popup is currently mounted on the screen.
      #   May not be visible.
      def open?
        screen.has_popup?(self)
      end

      # Moves window to center it on screen. Consults the window's
      # {Rect#width} and {Rect#height} and modifies {Rect#top} and {Rect#left}.
      # @return [void]
      def center
        self.rect = rect.centered(screen.size.width, screen.size.height)
      end

      # Assigns content and auto-sizes the window to fit it.
      # @param content [Component, nil]
      # @return [void]
      def content=(content)
        super
        update_rect unless content.nil?
      end

      # The max height of the window, defaults to 12 (10 rows + 2 chars border).
      # When the content is a {Component::List} with more items than fit, the
      # cursor is enabled automatically so the list can scroll.
      # @return [Integer]
      def max_height = 12

      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return true if super

        if [Keys::ESC, "q"].include?(key)
          close
          true
        else
          false
        end
      end

      private

      # Recalculates window width/height and recenters the window if it's open.
      # Called after the window content is changed.
      # @return [void]
      def update_rect
        size = content_size.clamp_height(max_height)
        # Clamp it to 80% of screen width/height.
        size = size.clamp(screen.size.width * 4 / 5, screen.size.height * 4 / 5)
        self.rect = Rect.new(-1, -1, size.width, size.height)
        center if open?
        # If we need to scroll since there's just too much stuff to show, enable
        # cursor — only meaningful for List content.
        if content.is_a?(Component::List) && content.content.length > max_height
          content.cursor = Component::List::Cursor.new
        end
      end
    end
  end
end
