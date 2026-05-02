# frozen_string_literal: true

module Tuile
  class Component
    # A {Window} that lists options identified by single keyboard keys, asks
    # the user to pick one, and fires a callback with the picked key.
    #
    # Usable tiled (just add to a {Layout} and read picks via the block) or
    # as a popup via {.open}, which wraps it in a {Popup} that closes itself
    # after a pick. ESC / `q` close without firing the callback.
    class PickerWindow < Window
      # Scrolls the window when more items.
      # @return [Integer]
      MAX_ITEMS = 10

      # One picker option.
      #
      # @!attribute [r] key
      #   @return [String] the keyboard key that picks this option.
      # @!attribute [r] caption
      #   @return [String] the option caption.
      class Option < Data.define(:key, :caption)
      end

      # @param caption [String] the window caption.
      # @param options [Array<Array(String, String)>] pairs of keyboard key and
      #   option caption. No Rainbow formatting must be used.
      # @yield [key] called with the option key once one is selected by the
      #   user. Not called if the picker is dismissed without picking.
      # @yieldparam key [String] the picked option key.
      # @yieldreturn [void]
      def initialize(caption, options, &block)
        raise ArgumentError, "block required" unless block
        raise ArgumentError, "options must not be empty" if options.empty?

        super(caption)
        @options = options.map { Option.new(it[0], it[1]) }
        @block = block
        list = Component::List.new
        list.content = @options.map { "#{it.key} #{Rainbow(it.caption).cadetblue}" }
        list.cursor = Component::List::Cursor.new
        list.on_item_chosen = ->(index, _line) { select_option(@options[index].key) }
        self.content = list
        # Optional hook for a containing Popup to dismiss itself after a pick.
        @on_pick = nil
      end

      # Callback invoked after the user picks an option (after the block
      # fires). The {Popup} returned by {.open} sets this to its own `close`.
      # @return [Proc, nil]
      attr_accessor :on_pick

      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return true if super

        if @options.any? { it.key == key }
          select_option(key)
          true
        else
          false
        end
      end

      def keyboard_hint
        @options.map { "#{it.key} #{Rainbow(it.caption).cadetblue}" }.join("  ")
      end

      # Opens a picker as a popup. Picking an option fires `block`, then
      # closes the popup; ESC / `q` close without firing `block`.
      # @param caption [String]
      # @param options [Array<Array(String, String)>]
      # @yield [key]
      # @yieldparam key [String]
      # @yieldreturn [void]
      # @return [Popup] the wrapping popup.
      def self.open(caption, options, &block)
        picker = PickerWindow.new(caption, options, &block)
        popup = Popup.new(content: picker)
        picker.on_pick = -> { popup.close }
        popup.open
        popup
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
