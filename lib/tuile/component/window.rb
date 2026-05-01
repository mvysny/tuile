# frozen_string_literal: true

module Tuile
  class Component
    # A window with a frame, a {#caption} and a content {Component}. Doesn't
    # support overlapping with other windows: it paints its entire contents and
    # doesn't clip if there are other overlapping windows.
    #
    # By default {Component::List} is set as the `content` {Component}.
    #
    # Window is considered invisible if {#rect} is empty or one of left/top is
    # negative. The window won't draw when invisible.
    class Window < Component
      include Component::HasContent

      # @return [Component, nil]
      attr_reader :content

      def content=(content)
        if content.is_a?(Array)
          # TODO: for compatibility reasons, refactor/remove
          @content.content = content
          return
        end
        super
        @content = content
      end

      def initialize(caption = "")
        super()
        @border_right = 1
        @caption = caption
        # Optional bottom-row chrome that overlays the bottom border (e.g. a
        # search field).
        @footer = nil
        self.content = Component::List.new
      end

      # @return [Component, nil] optional component overlaying the bottom border
      #   row.
      attr_reader :footer

      # Sets the bottom-row chrome slot. The footer overlays the bottom border at
      # full inner width and is positioned automatically; pass `nil` to remove.
      #
      # Symmetric to {#content=}: validates the new component, swaps parent
      # pointers, invalidates the old/new components and the window border, and
      # repairs focus via {#on_child_removed} if the removed footer held it.
      # @param new_footer [Component, nil]
      def footer=(new_footer)
        raise unless new_footer.nil? || new_footer.is_a?(Component)
        return if @footer == new_footer
        raise if !new_footer.nil? && !new_footer.parent.nil?

        old = @footer
        old&.parent = nil
        @footer = new_footer
        unless new_footer.nil?
          new_footer.parent = self
          new_footer.invalidate
          layout_footer
        end
        invalidate # repaint border row that the footer covers/uncovers
        on_child_removed(old) unless old.nil?
      end

      def children
        @footer.nil? ? super : super + [@footer]
      end

      def handle_key(key)
        return @footer.handle_key(key) if @footer&.active?

        super
      end

      def handle_mouse(event)
        if @footer && @footer.rect.contains?(event.x, event.y)
          @footer.handle_mouse(event)
        else
          super
        end
      end

      def rect=(new_rect)
        super
        layout_footer
      end

      # @param value [Boolean]
      def scrollbar=(value)
        content.scrollbar_visibility = value ? :visible : :gone
        @border_right = value ? 0 : 1
        invalidate
        layout(content)
      end

      # @return [String] the current caption, empty by default.
      attr_reader :caption

      # Sets new caption and repaints the window.
      # @param new_caption [String]
      def caption=(new_caption)
        @caption = new_caption
        invalidate
      end

      # @return [String] formatted keyboard hint for users. Empty by default.
      #   Example: `p #{Rainbow('Power').cadetblue}`. If the window responds to
      #   keys, override {#handle_key}.
      def keyboard_hint
        ""
      end

      # @return [Boolean] true if {#rect} is off screen and the window won't
      #   paint.
      def visible?
        !@rect.empty? && !@rect.top.negative? && !@rect.left.negative?
      end

      # Removes the window from the screen.
      def close
        screen.remove_popup(self)
      end

      # @return [Boolean] true if this window is part of a screen. May not be
      #   visible.
      def open?
        screen.has_popup?(self)
      end

      # Fully repaints the window: both frame and contents.
      def repaint
        super
        repaint_border
        # Border paints over content: invalidate the content to have it
        # repainted.
        content&.invalidate
      end

      def key_shortcut=(key)
        super
        # The shortcut key is shown in the caption — repaint.
        invalidate
      end

      protected

      def layout(content)
        content.rect = Rect.new(rect.left + 1, rect.top + 1, rect.width - 1 - @border_right, rect.height - 2)
      end

      # Paints the window border.
      def repaint_border
        return unless visible?

        caption = @caption || ""
        caption = "[#{key_shortcut}]-#{caption}" unless key_shortcut.nil?
        frame = TTY::Box.frame(
          width: @rect.width, height: @rect.height, top: @rect.top, left: @rect.left,
          title: { top_left: caption }
        )
        frame = Rainbow(frame).green if active?
        screen.print frame
      end

      private

      def layout_footer
        return if @footer.nil? || rect.empty?

        width = [rect.width - 2, 0].max
        @footer.rect = Rect.new(rect.left + 1, rect.top + rect.height - 1, width, 1)
      end
    end
  end
end
