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
    # show `[ caption ]` — that natural width is `caption.display_width + 4`.
    # A narrower {#rect} truncates the label with an ellipsis.
    class Button < Component
      # @param caption [String, StyledString, nil] the button's label, coerced
      #   the same way {#caption=} coerces it.
      # @yield optional `on_click` callback; same as assigning {#on_click=}.
      def initialize(caption = nil, &on_click)
        super()
        @caption = StyledString.parse(caption)
        @on_click = on_click
      end

      # @return [StyledString] the button's label. Empty by default.
      attr_reader :caption

      # Callback fired when the button is activated (Enter, Space, or
      # left-click). The callable receives no arguments.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_click

      # Sets a new caption and invalidates the button. No-op if unchanged. A
      # `String` is parsed via {StyledString.parse} (embedded ANSI is honored);
      # a {StyledString} is used as-is; `nil` empties the caption.
      # @param new_caption [String, StyledString, nil]
      # @return [void]
      def caption=(new_caption)
        new_caption = StyledString.parse(new_caption)
        return if @caption == new_caption

        @caption = new_caption
        invalidate
      end

      def focusable? = true

      def tab_stop? = true

      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
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

      # Paints `[ caption ]` on the top row of {#rect}, ellipsized to
      # `rect.width` — by *display* width, so a double-width caption can't
      # overrun the rect. The rest of {#rect} is cleared by `super`.
      # @return [void]
      def repaint
        super
        return if rect.empty?

        label = (StyledString.plain("[ ") + @caption + StyledString.plain(" ]")).ellipsize(rect.width)
        label = label.with_bg(screen.theme.active_bg_color) if active?
        draw_line(rect.left, rect.top, label)
      end
    end
  end
end
