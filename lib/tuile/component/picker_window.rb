# frozen_string_literal: true

module Tuile
  class Component
    # A popup that asks the user to pick one of `options`, identified by single
    # keyboard keys. Closes via ESC or `q` without firing the callback.
    class PickerWindow < PopupWindow
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
      #   user. Not called if the window is closed via ESC or q.
      # @yieldparam key [String] the picked option key.
      # @yieldreturn [void]
      def initialize(caption, options, &block)
        raise "no options" if options.empty?

        super(caption)
        options = options.map { Option.new(it[0], it[1]) }
        @options = options
        @block = block
        list = Component::List.new
        list.content = options.map { "#{it.key} #{Rainbow(it.caption).cadetblue}" }
        list.cursor = Component::List::Cursor.new
        list.on_item_chosen = ->(index, _line) { select_option(@options[index].key) }
        self.content = list
      end

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

      # @param caption [String] the window caption.
      # @param options [Array<Array(String, String)>] pairs of keyboard key and
      #   option caption. No Rainbow formatting must be used.
      # @yield [key] called with the option key once one is selected by the
      #   user. Not called if the window is closed via ESC or q.
      # @yieldparam key [String] the picked option key.
      # @yieldreturn [void]
      # @return [PickerWindow]
      def self.open(caption, options, &block)
        picker = PickerWindow.new(caption, options, &block)
        picker.open
        picker
      end

      protected

      # @param key [String]
      # @return [void]
      def select_option(key)
        @block.call(key)
        close
      end
    end
  end
end
