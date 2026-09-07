# frozen_string_literal: true

module Tuile
  class Component
    # A {Window} that lists options identified by single keyboard keys, asks
    # the user to pick one, and fires a callback with the picked key. Each row
    # is `"<key> <caption>"`:
    #
    #   PickerWindow.open("Sort by", [%w[n name], %w[s size]]) { sort_by(_1) }
    #
    #   ┌Sort by───────┐
    #   │n name        │
    #   │s size        │
    #   └──────────────┘
    #
    # Usable tiled (just add to a {Layout} and read picks via the block) or
    # as a popup via {.open}, which wraps it in a {Popup} that closes itself
    # after a pick. ESC / `q` close without firing the callback.
    #
    # Captions paint in the terminal's own foreground. To color them, hand in
    # {StyledString} captions — the picker styles nothing itself, so an app's
    # own token applies per option:
    #
    #   PickerWindow.open("File", [["o", StyledString.plain("Open")],
    #                              ["d", theme.fg(:danger, "Delete")]]) { … }
    class PickerWindow < Window
      # Scrolls the window when more items.
      # @return [Integer]
      MAX_ITEMS = 10

      # One picker option.
      #
      # @!attribute [r] key
      #   @return [String] the keyboard key that picks this option.
      # @!attribute [r] caption
      #   @return [StyledString] the option caption, coerced from whatever the
      #     constructor was handed.
      class Option < Data.define(:key, :caption)
      end

      # @param caption [String] the window caption.
      # @param options [Array<Array(String, String, StyledString)>] pairs of
      #   keyboard key and option caption. A caption goes through
      #   {StyledString.parse}, so a plain String, an ANSI-coded one (what
      #   {Theme#fg} returns) and a {StyledString} are all accepted.
      # @yield [key] called with the option key once one is selected by the
      #   user. Not called if the picker is dismissed without picking.
      # @yieldparam key [String] the picked option key.
      # @yieldreturn [void]
      # @raise [ArgumentError] when `block` is missing or `options` is empty.
      def initialize(caption, options, &block)
        raise ArgumentError, "block required" unless block
        raise ArgumentError, "options must not be empty" if options.empty?

        super(caption)
        @options = options.map { Option.new(_1[0], StyledString.parse(_1[1])) }
        @block = block
        list = Component::List.new
        list.renderer = ->(option) { StyledString.plain("#{option.key} ") + option.caption }
        list.items = @options
        list.cursor = Component::List::Cursor.new
        list.on_item_chosen = ->(_index, option) { select_option(option.key) }
        self.content = list
        # Optional hook for a containing Popup to dismiss itself after a pick.
        @on_pick = nil
      end

      # Callback invoked after the user picks an option (after the block
      # fires). The {Popup} returned by {.open} sets this to its own `close`.
      # @return [Proc, nil]
      attr_accessor :on_pick

      # Handles an option-key press. Reached by bubbling: the inner {List}
      # (the focused component) sees the key first and handles cursor/Enter
      # picks; anything it declines bubbles up here, where a key matching an
      # option's `key` picks that option.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        if @options.any? { _1.key == key }
          select_option(key)
          true
        else
          false
        end
      end

      # Opens a picker as a popup. Picking an option fires `block`, then
      # closes the popup; ESC / `q` close without firing `block`.
      # @param caption [String]
      # @param options [Array<Array(String, String, StyledString)>]
      # @yield [key]
      # @yieldparam key [String]
      # @yieldreturn [void]
      # @return [Popup] the wrapping popup.
      def self.open(caption, options, &block)
        picker = PickerWindow.new(caption, options, &block)
        popup = Popup.new(content: picker)
        picker.on_pick = -> { popup.close }
        popup.open
      end

      protected

      # @param key [String]
      # @return [void]
      def select_option(key)
        @block.call(key)
        @on_pick&.call
      end
    end
  end
end
