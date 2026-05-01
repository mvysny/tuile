# frozen_string_literal: true

module Tuile
  class Component
    # A popup window. Adds {#open} which opens the window; the window closes
    # automatically when 'q' or ESC is pressed.
    #
    # The window also sets its size automatically, based on the contents set.
    # {#max_height} is consulted.
    class PopupWindow < Window
      # Opens the popup window.
      # @return [void]
      def open
        screen.add_popup(self)
      end

      # Moves window to center it on screen. Consults the window's
      # {Rect#width} and {Rect#height} and modifies {Rect#top} and {Rect#left}.
      # @return [void]
      def center
        self.rect = rect.centered(screen.size.width, screen.size.height)
      end

      # @param content [Component, Array<String>, nil]
      # @return [void]
      def content=(content)
        if content.is_a?(Array)
          # TODO: for compatibility reasons, refactor/remove
          @content.content = content
          update_rect
        else
          super
        end
      end

      # The max height of the window, defaults to 12 (10 rows + 2 chars border).
      # The window automatically enables cursor + scrolling when there are more
      # items.
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
        size = content.content_size.plus(2, 2).clamp_height(max_height)
        # Clamp it to 80% of screen width/height.
        size = size.clamp(screen.size.width * 4 / 5, screen.size.height * 4 / 5)
        self.rect = Rect.new(-1, -1, size.width, size.height)
        center if open?
        # If we need to scroll since there's just too much stuff to show, enable
        # cursor.
        content.cursor = Component::List::Cursor.new if content.content.length > max_height
      end
    end
  end
end
