# frozen_string_literal: true

module Tuile
  class Component
    # A clickable button. Activated by Enter, Space, or a left mouse click;
    # fires the {#on_click} callback. Renders as `[ caption ]` on a single
    # row; the background is highlighted when the button is focused so the
    # user can see which button is active.
    #
    # Buttons are tab stops — Tab and Shift+Tab will land on them as part of
    # the standard focus cycle. Click-to-focus also works via the inherited
    # {Component#handle_mouse}.
    #
    # Assign a {#rect} (typically by the surrounding {Layout}) wide enough to
    # show `[ caption ]`; {#content_size} reports that natural width.
    class Button < Component
      # @param caption [String] the button's label.
      # @yield optional `on_click` callback; same as assigning {#on_click=}.
      def initialize(caption = "", &on_click)
        super()
        @caption = caption.to_s
        @on_click = on_click
      end

      # @return [String] the button's label.
      attr_reader :caption

      # Callback fired when the button is activated (Enter, Space, or
      # left-click). The callable receives no arguments.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_click

      # Sets a new caption and invalidates the button. No-op if unchanged.
      # @param new_caption [String]
      def caption=(new_caption)
        new_caption = new_caption.to_s
        return if @caption == new_caption

        @caption = new_caption
        invalidate
      end

      def focusable? = true

      def tab_stop? = true

      # @return [Size] natural width is `caption.length + 4` to fit
      #   `[ caption ]`; height is 1.
      def content_size = Size.new(@caption.length + 4, 1)

      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless active?
        return true if super

        case key
        when Keys::ENTER, " "
          @on_click&.call
          true
        else
          false
        end
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left && rect.contains?(event.point)

        @on_click&.call
      end

      # @return [void]
      def repaint
        clear_background
        return if rect.empty?

        label = "[ #{@caption} ]"[0, rect.width]
        styled = active? ? Rainbow(label).bg(:darkslategray) : label
        screen.print TTY::Cursor.move_to(rect.left, rect.top), styled
      end
    end
  end
end
