# frozen_string_literal: true

module Tuile
  class Component
    # The confirm dialog: a {Window} asking a question — a caption, a prose
    # {#message}, a centered row of buttons — plus the one-button degenerate
    # case, the alert. Three factories cover the common shapes and open the
    # dialog as a centered, content-sized {Popup}:
    #
    #   Component::ConfirmWindow.alert("Export failed", "Contact support@example.com.")
    #   Component::ConfirmWindow.confirm("Delete Report Q4?", "This cannot be undone.",
    #                                    confirm: "Delete") { delete! }
    #   Component::ConfirmWindow.yes_no("Overwrite file?", "target.txt already exists.") { overwrite! }
    #
    # The component itself is the builder — declare any button set through
    # {#button}, then {#open}:
    #
    #   dialog = Component::ConfirmWindow.new("Unsaved changes")
    #   dialog.message = "Save your changes before leaving?"
    #   dialog.button("Save")    { save! }
    #   dialog.button("Discard") { discard! }
    #   dialog.button("Cancel")             # no action: pressing it dismisses
    #   dialog.on_dismiss = -> { stay_put }
    #   dialog.open
    #
    # **Every button closes the dialog.** A button with a block then fires it; a
    # button without one is a Cancel. ESC, `q`, an outside click and a Cancel
    # button are all one outcome — {#on_dismiss}, fired exactly once, and only
    # when no action button was chosen. There is deliberately no keep-open knob:
    # a dialog that leads somewhere opens the next window from its callback.
    #
    # Keys: Left/Right (and Tab) move between the buttons, Enter/Space press the
    # focused one, and each button answers to its underlined mnemonic letter
    # (see {#button}). The message scrolls without taking focus —
    # {BODY_SCROLL_KEYS} are handed to it from anywhere in the dialog. Focus
    # opens on the first button; Shift+Tab reaches the message, a tab stop of
    # its own.
    #
    # The popup sizes itself from what the dialog owns — caption, message,
    # buttons — capped at half the screen ({#measured_size}), re-measured when
    # any of them changes. Usable tiled too (add it to a {Layout}): buttons then
    # fire their callbacks with nothing to close.
    #
    # There is deliberately no content slot: the body is prose ({#message=}
    # takes a component for the rare rich body, but the dialog then cannot
    # measure it). A dialog collecting *input* is not a confirm dialog — build a
    # `Popup.new(content: your_layout)`. See `DECISIONS.md` `D_confirm_window`
    # for the API rationale.
    class ConfirmWindow < Window
      # Keys handed to the message body from anywhere in the dialog, so it
      # scrolls while a button keeps focus. The printables among them (`g`/`G`,
      # the less/vi top/bottom idiom) are {RESERVED_MNEMONICS} in exchange.
      #
      # Deliberately *not* `Keys::UP_ARROWS`/`DOWN_ARROWS`: those include the vi
      # aliases `j`/`k`, which stay available as mnemonics ("Keep") — the body
      # still honors them when focused itself.
      # @return [Array<String>]
      BODY_SCROLL_KEYS = ([Keys::UP_ARROW, Keys::DOWN_ARROW, Keys::PAGE_UP, Keys::PAGE_DOWN,
                           Keys::CTRL_U, Keys::CTRL_D, "g", "G"] + Keys::HOMES + Keys::ENDS_).freeze

      # Letters {#button} refuses as a mnemonic, compared downcased: `q` is
      # unconditionally the dismiss key (a {Popup} claims it below this window),
      # and `g`/`G` scroll the message ({BODY_SCROLL_KEYS}).
      # @return [Array<String>]
      RESERVED_MNEMONICS = %w[q g].freeze

      # Border rows plus the body-to-buttons spacing plus the button row — what
      # {#measured_size} adds to the wrapped message rows.
      # @return [Integer]
      HEIGHT_CHROME = 4
      # Border columns plus the body padding — what {#measured_size} adds to the
      # widest message line, and subtracts to find the wrap width.
      # @return [Integer]
      WIDTH_CHROME = 4
      private_constant :HEIGHT_CHROME, :WIDTH_CHROME

      # @param caption [String, StyledString, nil] the border title, coerced the
      #   same way {HasCaption#caption=} coerces it.
      def initialize(caption = nil)
        @popup = nil
        @chosen = false
        @message = nil
        @on_dismiss = nil
        # Insertion-ordered; identity-keyed so equal captions stay two buttons.
        @actions = {}.compare_by_identity
        @mnemonics = {}
        super(caption)
        @body_slot = Slot.new
        @button_row = Layout::Horizontal.new(spacing: 2)
        @box = Layout::Vertical.new(spacing: 1, padding: Layout::Insets[left: 1, right: 1])
        @box.add(@body_slot, Layout::Expand[1])
        @box.add(@button_row, Layout::Fixed[1], cross: Layout::Fixed[0], align: :center)
        self.content = @box
      end

      # Callback taking no arguments, fired when the dialog is dismissed — ESC,
      # `q`, an outside click, or a {#button} declared without a block. Fires
      # exactly once per {#open}, and never when an action button was chosen.
      # @return [Proc, nil]
      attr_accessor :on_dismiss

      # @return [String, StyledString, Component, nil] whatever {#message=} was
      #   given — set a `String`, read that `String` back. The component
      #   rendering it is derived, never returned.
      attr_reader :message

      # Also re-measures the popup: the caption participates in the width.
      # @param new_caption [String, StyledString, nil]
      # @return [void]
      def caption=(new_caption)
        super
        resize_popup
      end

      # Sets the dialog body. Text (`String` / {StyledString}) is rendered by a
      # word-wrapping, scrollable {TextView} the dialog owns and measures; a
      # {Component} is mounted as-is, and the dialog — which may measure only
      # content it owns — then takes the full half-screen box. `nil` clears.
      # @param value [String, StyledString, Component, nil]
      # @raise [TypeError] on any other type.
      # @return [void]
      def message=(value)
        occupant =
          case value
          when nil then nil
          when Component then value
          when String, StyledString then TextView.new.tap { _1.text = value }
          else raise TypeError, "expected String, StyledString, Component or nil, got #{value.inspect}"
          end
        @message = value
        @body_slot.content = occupant
        resize_popup
      end

      # Appends a button and returns it. A button with a block is an action
      # button: pressing it closes the dialog, then fires the block. A button
      # without one is a Cancel: pressing it closes the dialog, then fires
      # {#on_dismiss}.
      #
      #   dialog.button("Delete") { delete! }        # mnemonic d, underlined
      #   dialog.button("Keep", mnemonic: "e")       # explicit letter
      #   dialog.button("Cancel", mnemonic: nil)     # no mnemonic
      #
      # The mnemonic — a printable letter activating the button from anywhere in
      # the dialog, case-insensitively — is underlined in the caption. The
      # default `:auto` derives the caption's first letter and is best-effort:
      # silently skipped when that letter is reserved, taken, or unusable. An
      # explicit letter is a promise and raises when it cannot be kept.
      #
      # Declare buttons before {#open}: adding one to an open dialog re-measures
      # the popup, but momentarily bounces focus off the button row.
      # @param caption [String, StyledString] the button label.
      # @param mnemonic [Symbol, String, nil] `:auto` (default), a printable
      #   one-column character, or `nil` for none.
      # @yield optional action, fired after the dialog closes.
      # @raise [ArgumentError] on an explicit mnemonic that is reserved
      #   ({RESERVED_MNEMONICS}), a space, already taken, or not a one-column
      #   printable.
      # @return [Button] the appended button.
      def button(caption, mnemonic: :auto, &action)
        styled = StyledString.parse(caption)
        letter = resolve_mnemonic(styled, mnemonic)
        btn = Button.new(letter ? underline_mnemonic(styled, letter) : styled)
        btn.on_click = -> { activate(btn) }
        @actions[btn] = action
        @mnemonics[letter] = btn unless letter.nil?
        @button_row.add(btn, Layout::Fixed[btn.caption.display_width + 4])
        recenter_button_row
        resize_popup
        btn
      end

      # Opens the dialog as a centered modal {Popup} sized by {#measured_size}
      # and returns that popup. ESC, `q` and an outside click dismiss it
      # (firing {#on_dismiss}); every button closes it too.
      # @raise [Tuile::Error] if this dialog is already open.
      # @return [Popup] the mounted popup; `popup.close` closes programmatically,
      #   as {#close} also does.
      def open
        raise Tuile::Error, "#{inspect} is already open" if @popup&.open?

        # A previous popup still holds this window as its content; reclaim it.
        @popup&.content = nil
        @chosen = false
        @popup = MeasuredPopup.new(self)
        @popup.on_close = -> { notice_dismissed }
        @popup.open
      end

      # Closes the popup {#open} mounted, which counts as a dismissal
      # ({#on_dismiss} fires). No-op when not open, or when used tiled.
      # @return [void]
      def close = @popup&.close

      # The popup box this dialog wants: wide enough for the caption, the widest
      # message line and the button row, tall enough for the wrapped message
      # plus the button row — each capped at half of `reference`. The re-grow
      # rule's caller-side measure query: the dialog measures only content it
      # *owns*, so a {Component} assigned to {#message=} yields the full
      # half-screen box.
      # @param reference [Size] the screen size to cap against.
      # @return [Size]
      def measured_size(reference = screen.size)
        cap = Fraction::HALF.resolve(reference)
        return cap if @message.is_a?(Component)

        styled = @message.nil? ? StyledString::EMPTY : StyledString.parse(@message)
        widest = styled.lines.map(&:display_width).max || 0
        width = [[caption.display_width + 2, button_row_width + WIDTH_CHROME, widest + WIDTH_CHROME].max,
                 cap.width].min
        rows = styled.empty? ? 0 : styled.wrap([width - WIDTH_CHROME, 1].max).size
        Size.new(width, [rows + HEIGHT_CHROME, cap.height].min)
      end

      # Focus lands on the first button rather than cascading into the message
      # body, which sits before the button row in the tree.
      # @return [void]
      def on_focus
        first = @actions.keys.first
        if first.nil?
          super
        else
          screen.focused = first
        end
      end

      # Handles the dialog-wide keys: Left/Right move between the buttons,
      # {BODY_SCROLL_KEYS} are hand-fed to the message body, and a mnemonic
      # letter presses its button. Reached by bubbling — the focused button or
      # body sees the key first, so a focused body consumes its own scroll keys
      # before this runs.
      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_key(key)
        case key
        when Keys::LEFT_ARROW then return focus_button_step(-1)
        when Keys::RIGHT_ARROW then return focus_button_step(1)
        when *BODY_SCROLL_KEYS then return @body_slot.content&.handle_key(key) || false
        end

        target = @mnemonics[key.downcase]
        return false if target.nil?

        activate(target)
        true
      end

      # Opens an acknowledgement dialog: a message and one button, whose press
      # is the dismissal. The button exists for discoverability — ESC and `q`
      # close too, but Tuile advertises no keys anywhere, and the button is
      # clickable.
      # @param caption [String, StyledString, nil] the border title.
      # @param message [String, StyledString, Component, nil] see {#message=}.
      # @param button [String, StyledString] the button label.
      # @return [Popup] the mounted popup.
      def self.alert(caption, message, button: "OK")
        window = new(caption)
        window.message = message
        window.button(button)
        window.open
      end

      # Opens a two-button question: the block is the action, the cancel button
      # (with ESC, `q` and an outside click) is the dismissal.
      #
      #   Component::ConfirmWindow.confirm("Delete Report Q4?", "This cannot be undone.",
      #                                    confirm: "Delete") { delete! }
      #
      # @param caption [String, StyledString, nil] the border title.
      # @param message [String, StyledString, Component, nil] see {#message=}.
      # @param confirm [String, StyledString] the action button's label.
      # @param cancel [String, StyledString] the dismissal button's label.
      # @param on_dismiss [Proc, nil] see {#on_dismiss}.
      # @yield the action, fired after the dialog closes.
      # @raise [ArgumentError] without a block — a confirm without an action is
      #   an {.alert}.
      # @return [Popup] the mounted popup.
      def self.confirm(caption, message, confirm: "Confirm", cancel: "Cancel", on_dismiss: nil, &action)
        raise ArgumentError, "block required" unless action

        window = new(caption)
        window.message = message
        window.button(confirm, &action)
        window.button(cancel)
        window.on_dismiss = on_dismiss
        window.open
      end

      # {.confirm} with Yes/No labels — the other canonical phrasing.
      # @param caption [String, StyledString, nil] the border title.
      # @param message [String, StyledString, Component, nil] see {#message=}.
      # @param on_dismiss [Proc, nil] see {#on_dismiss}.
      # @yield the action, fired on Yes after the dialog closes.
      # @raise [ArgumentError] without a block.
      # @return [Popup] the mounted popup.
      def self.yes_no(caption, message, on_dismiss: nil, &action)
        confirm(caption, message, confirm: "Yes", cancel: "No", on_dismiss:, &action)
      end

      # The {Popup} that {#open} wraps the dialog in: its declared size is
      # derived from the dialog on every {#reposition}, so a message change and
      # a SIGWINCH both re-measure against the current screen.
      class MeasuredPopup < Popup
        # @param window [ConfirmWindow]
        def initialize(window)
          # Before super: Popup#initialize ends in the first #reposition call.
          @window = window
          super(content: window)
        end

        # @return [void]
        def reposition
          # The ivar, not #declared_size= — the writer calls reposition itself.
          @declared_size = @window.measured_size(screen.size)
          super
        end
      end
      private_constant :MeasuredPopup

      private

      # The chosen-button path, in the settled order: mark chosen, close the
      # popup (whose on_close then skips the dismissal), fire the callback last
      # so it sees the dialog already gone — a callback opening a follow-up
      # popup gets clean focus-repair state.
      # @param btn [Button]
      # @return [void]
      def activate(btn)
        action = @actions[btn]
        @chosen = true
        @popup&.close
        action.nil? ? @on_dismiss&.call : action.call
      end

      # The popup's on_close: fires {#on_dismiss} unless a button was chosen —
      # which makes ESC, `q`, an outside click, {#close}, a direct
      # {Screen#remove_popup} and teardown all one event, fired exactly once.
      # @return [void]
      def notice_dismissed
        return if @chosen

        @chosen = true
        @on_dismiss&.call
      end

      # @param delta [Integer] -1 or 1.
      # @return [Boolean] false when focus is not on a button (the key bubbles on).
      def focus_button_step(delta)
        buttons = @actions.keys
        current = buttons.index(screen.focused)
        return false if current.nil?

        screen.focused = buttons[(current + delta) % buttons.size]
        true
      end

      # Validates an explicit mnemonic (raising, as {MenuBar#add_item} does —
      # none of these has a sane answer at keypress time) or best-effort derives
      # one from the caption's first letter (returning nil where the explicit
      # path would raise).
      # @param caption [StyledString]
      # @param mnemonic [Symbol, String, nil]
      # @raise [ArgumentError] see {#button}.
      # @return [String, nil] the downcased letter, or nil for none.
      def resolve_mnemonic(caption, mnemonic)
        return nil if mnemonic.nil?
        return derive_mnemonic(caption) if mnemonic == :auto

        raise ArgumentError, "mnemonic must not be a space: Space presses the focused button" if mnemonic == " "
        unless Keys.printable?(mnemonic) && StyledString.plain(mnemonic).display_width == 1
          raise ArgumentError, "mnemonic must be a single one-column printable character; got #{mnemonic.inspect}"
        end

        down = mnemonic.downcase
        if RESERVED_MNEMONICS.include?(down)
          raise ArgumentError, "mnemonic #{down.inspect} is reserved: q dismisses the dialog, g/G scroll the message"
        end
        raise ArgumentError, "duplicate mnemonic #{down.inspect}" if @mnemonics.key?(down)

        down
      end

      # @param caption [StyledString]
      # @return [String, nil]
      def derive_mnemonic(caption)
        letter = caption.to_s.grapheme_clusters.first&.downcase
        return nil if letter.nil? || letter == " "
        return nil unless Keys.printable?(letter) && StyledString.plain(letter).display_width == 1
        return nil if RESERVED_MNEMONICS.include?(letter) || @mnemonics.key?(letter)

        letter
      end

      # {StyledString#slice} counts **columns** while a caption search yields a
      # **character** index, so the prefix is measured, never counted (the
      # {MenuBar::Item} cue, duplicated per `D_float_field`'s shallow-shell rule).
      # @param caption [StyledString]
      # @param letter [String] downcased.
      # @return [StyledString]
      def underline_mnemonic(caption, letter)
        text = caption.to_s
        index = text.index(letter) || text.downcase.index(letter)
        return caption if index.nil?

        start = StyledString.plain(text[0, index]).display_width
        caption.slice(0, start) + caption.slice(start, 1).with_underline +
          caption.slice(start + 1, caption.display_width - start - 1)
      end

      # Re-declares the button row's cross extent — the buttons' summed natural
      # width — so the {Layout::Vertical} centers it. Remove-and-re-add is the
      # only way to change a {Layout::Box} constraint; the row stays after the
      # body because both `add`s append.
      # @return [void]
      def recenter_button_row
        @box.remove(@button_row)
        @box.add(@button_row, Layout::Fixed[1], cross: Layout::Fixed[button_row_width], align: :center)
      end

      # @return [Integer] columns of the button row at its natural width.
      def button_row_width
        widths = @actions.keys.map { _1.caption.display_width + 4 }
        widths.sum + (@button_row.spacing * [widths.size - 1, 0].max)
      end

      # Re-measures the popup while open; a no-op tiled or before {#open}.
      # @return [void]
      def resize_popup
        @popup.reposition if @popup&.open?
      end
    end
  end
end
