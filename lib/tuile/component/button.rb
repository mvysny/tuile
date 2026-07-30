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
    # A narrower {#rect} truncates the label with an ellipsis; a wider one leaves
    # a tail that focuses but doesn't activate (see {#extent}).
    class Button < Component
      include Component::HasCaption

      # @param caption [String, StyledString, nil] the button's label, coerced
      #   the same way {HasCaption#caption=} coerces it.
      # @yield optional `on_click` callback; same as assigning {#on_click=}.
      def initialize(caption = nil, &on_click)
        super()
        self.caption = caption
        @on_click = on_click
      end

      # Callback fired when the button is activated (Enter, Space, or
      # left-click). The callable receives no arguments.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_click

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

      # The cells the button actually paints: one row, `caption.display_width + 4`
      # columns, clipped to {#rect}. Both the focus highlight and the click hit
      # test use it, so a click on the blank tail of an over-wide rect — or on a
      # lower row, when the rect is taller than one — does not fire {#on_click}.
      # It still *focuses*: {Component#handle_mouse}'s click-to-focus is ungated
      # by geometry. Same rule as {Checkbox#extent}, which documents the two
      # traps behind it.
      # @return [Rect]
      def extent = Rect.new(rect.left, rect.top, [caption.display_width + 4, rect.width].min, 1)

      # Fires {#on_click} on a left click within {#extent}; `super` runs first, so
      # a click anywhere in {#rect} still focuses.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left && extent.contains?(event.point)

        @on_click&.call
      end

      # @return [void]
      def repaint
        super
        return if rect.empty?

        label = (StyledString.plain("[ ") + caption + StyledString.plain(" ]")).ellipsize(rect.width)
        label = label.with_bg(screen.theme.active_bg_color) if active?
        draw_line(rect.left, rect.top, label)
      end
    end
  end
end
