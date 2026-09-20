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
    # {Component#handle_mouse_down?}.
    #
    # Assign a {#rect} (typically by the surrounding {Layout}) wide enough to
    # show `[ caption ]` — that natural width is `caption.display_width + 4`.
    # A narrower {#rect} truncates the label with an ellipsis; a wider one leaves
    # a tail that focuses but doesn't activate (see {#extent}).
    class Button < Component
      include Component::HasCaption

      # @param caption [String, StyledString, nil] the button's label, coerced
      #   the same way {HasCaption#caption=} coerces it.
      # @yield optional `on_click` listener; same as registering one on {#on_click}.
      def initialize(caption = nil, &listener)
        super()
        self.caption = caption
        on_click << listener if listener
      end

      # What {#on_click} fires.
      #
      # @!attribute [r] source
      #   @return [Button] the button that was activated.
      ClickEvent = Data.define(:source) { include Tuile::Event }

      # @!method on_click
      #   Fired with a {ClickEvent} when the button is activated — Enter, Space
      #   or a left click within {#extent}.
      #   @return [Listeners]
      listener :on_click

      def focusable? = true

      def tab_stop? = true

      # @param key [String]
      # @return [Boolean]
      def handle_key?(key)
        case key
        when Keys::ENTER, " "
          on_click.fire(ClickEvent.new(source: self))
          true
        else
          false
        end
      end

      # The cells the button actually paints: one row, `caption.display_width + 4`
      # columns, clipped to {#rect}. Both the focus highlight and the click hit
      # test use it, so a click on the blank tail of an over-wide rect — or on a
      # lower row, when the rect is taller than one — does not fire {#on_click}.
      # It still *focuses*: {Mouse::Router}'s click-to-focus is ungated
      # by geometry. Same rule as {Checkbox#extent}, which documents the two
      # traps behind it.
      # @return [Size]
      def extent = Size.new([caption.display_width + 4, rect.width].min, 1)

      # Fires {#on_click} on a left click within {#extent}; `super` runs first, so
      # a click anywhere in {#rect} still focuses.
      # @param event [Mouse::DownEvent]
      # @return [Boolean]
      def handle_mouse_down?(event)
        return false unless event.button == :left

        on_click.fire(ClickEvent.new(source: self))
        true
      end

      # @param canvas [Canvas] see {Component#repaint}.
      # @return [void]
      def repaint(canvas)
        super
        return if rect.empty?

        label = (StyledString.plain("[ ") + caption + StyledString.plain(" ]")).ellipsize(rect.width)
        label = label.with_bg(screen.theme.active_bg_color) if active?
        canvas.set_text(0, 0, label)
      end
    end
  end
end
