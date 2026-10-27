# frozen_string_literal: true

module Tuile
  class Component
    # A {Dialog} that lists options identified by single keyboard keys, asks
    # the user to pick one, fires a callback with the picked key and closes.
    # Each row is `"<key> <caption>"`:
    #
    #   PickerDialog.new("Sort by", [%w[n name], %w[s size]]) { sort_by(_1) }.open
    #
    #   ┌Sort by───────┐
    #   │n name        │
    #   │s size        │
    #   └──────────────┘
    #
    # ESC / `q` close it without firing the callback.
    #
    # Captions paint in the terminal's own foreground. To color them, hand in
    # {StyledString} captions — the picker styles nothing itself, so an app's
    # own token applies per option:
    #
    #   PickerDialog.new("File", [["o", StyledString.plain("Open")],
    #                             ["d", theme.fg(:danger, "Delete")]]) { … }
    #
    # An option that doesn't apply right now is *disabled* by a third element
    # naming why. It paints in {Theme#disabled_color}, reason appended and any
    # caption ink of the app's replaced, and picking it — key, Enter
    # or click — fires nothing and closes nothing; its key moves the cursor
    # onto it instead, so the reason is where the user is looking:
    #
    #   PickerDialog.new("Maintenance", [
    #     ["r", "Resize disk image…", { disabled: "shut the VM down first" }],
    #     ["g", "Grow root filesystem…"]
    #   ]) { … }
    #
    #   ┌Maintenance──────────────────────────────────┐
    #   │r Resize disk image… (shut the VM down first)│  ← disabled_color
    #   │g Grow root filesystem…                      │
    #   └─────────────────────────────────────────────┘
    #
    # The options are a snapshot taken at construction, as a desktop menu's
    # enabled state is taken when it opens: what changes while the picker is
    # up doesn't reach it. So disabling is a hint, never the guard — the block
    # still checks that its operation can run.
    class PickerDialog < Dialog
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
      # @!attribute [r] disabled_reason
      #   @return [String, nil] why the option can't be picked; `nil` when it
      #     can. A disabled option without a reason is refused.
      class Option < Data.define(:key, :caption, :disabled_reason)
        # @param key [String]
        # @param caption [StyledString]
        # @param disabled_reason [String, nil]
        # @raise [ArgumentError] when `disabled_reason` is neither `nil` nor a
        #   non-empty String — `disabled: true` included.
        def initialize(key:, caption:, disabled_reason: nil)
          unless disabled_reason.nil? || (disabled_reason.is_a?(String) && !disabled_reason.empty?)
            raise ArgumentError, "a disabled option needs a reason String, got #{disabled_reason.inspect}"
          end

          super
        end

        # @return [Boolean]
        def disabled? = !disabled_reason.nil?
      end

      # @param caption [String] the dialog caption.
      # @param options [Array<Array(String, StyledString), Array(String, StyledString, Hash)>]
      #   pairs of keyboard key and option caption, optionally followed by
      #   `{ disabled: reason }`. A caption goes through {StyledString.parse},
      #   so a plain String, an ANSI-coded one (what {Theme#fg} returns) and a
      #   {StyledString} are all accepted.
      # @yield [key] called with the option key once one is selected by the
      #   user. Not called if the picker is dismissed without picking.
      # @yieldparam key [String] the picked option key.
      # @yieldreturn [void]
      # @raise [ArgumentError] when `block` is missing, `options` is empty, or
      #   an option's Hash holds anything but a non-empty `disabled:` String.
      def initialize(caption, options, &block)
        raise ArgumentError, "block required" unless block
        raise ArgumentError, "options must not be empty" if options.empty?

        super(caption)
        @_options = options.map { |key, text, opts = {}| build_option(key, text, **opts) }
        @_block = block
        list = Component::List.new
        list.renderer = ->(option, _text_width) { render_option(option) }
        list.items = @_options
        list.cursor = Component::List::Cursor.new
        list.on_item_chosen { |e| select_option(e.item) }
        self.content = list
        on_pick { close }
      end

      # What {#on_pick} fires.
      #
      # @!attribute [r] source
      #   @return [PickerDialog] the picker whose option was chosen.
      PickEvent = Data.define(:source) { include Tuile::Event }

      # @!method on_pick
      #   Fired with a {PickEvent} after the user picks an option, after the
      #   block fires. The picker's own `close` is the first listener.
      #   @return [Listeners]
      listener :on_pick

      # Handles an option-key press. Reached by bubbling: the inner {List}
      # (the focused component) sees the key first and handles cursor/Enter
      # picks; anything it declines bubbles up here, where a key matching an
      # option's `key` picks that option, and the rest goes to
      # {Dialog#handle_key?}.
      # @param key [String]
      # @return [Boolean]
      def handle_key?(key)
        option = @_options.find { _1.key == key }
        return super if option.nil?

        select_option(option)
        true
      end

      protected

      # Re-renders the rows, which {List} caches with the disabled ink baked in.
      # @return [void]
      def handle_theme_changed
        super
        content.refresh_rows
      end

      # @param option [Option]
      # @return [void]
      def select_option(option)
        if option.disabled?
          content.select(@_options.index(option))
          return
        end

        @_block.call(option.key)
        on_pick.fire(PickEvent.new(source: self))
      end

      private

      # @param key [String]
      # @param text [String, StyledString]
      # @param disabled [String, nil]
      # @return [Option]
      def build_option(key, text, disabled: nil)
        Option.new(key:, caption: StyledString.parse(text), disabled_reason: disabled)
      end

      # @param option [Option]
      # @return [StyledString]
      def render_option(option)
        row = StyledString.plain("#{option.key} ") + option.caption
        return row unless option.disabled?

        (row + StyledString.plain(" (#{option.disabled_reason})")).with_fg(screen.theme.disabled_color)
      end
    end
  end
end
