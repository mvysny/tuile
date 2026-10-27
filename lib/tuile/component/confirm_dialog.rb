# frozen_string_literal: true

module Tuile
  class Component
    # The confirm dialog: a {Dialog} asking a question — a caption, a prose
    # {#message}, a centered row of buttons — plus the one-button degenerate
    # case, the alert. Three factories cover the common shapes and open it
    # centered and sized to its content:
    #
    #   Component::ConfirmDialog.alert("Export failed", "Contact support@example.com.")
    #   Component::ConfirmDialog.confirm("Delete Report Q4?", "This cannot be undone.",
    #                                    confirm: "Delete") { delete! }
    #   Component::ConfirmDialog.yes_no("Overwrite file?", "target.txt already exists.") { overwrite! }
    #
    # The component itself is the builder — declare any button set through
    # {#button}, then {#open}:
    #
    #   dialog = Component::ConfirmDialog.new("Unsaved changes")
    #   dialog.message = "Save your changes before leaving?"
    #   dialog.button("Save")    { save! }
    #   dialog.button("Discard") { discard! }
    #   dialog.button("Cancel")             # no action: pressing it dismisses
    #   dialog.on_dismiss { stay_put }
    #   dialog.open
    #
    # **Every button closes the dialog.** A button with a block then fires it; a
    # button without one is a Cancel. ESC, `q`, an outside click and a Cancel
    # button are all one outcome — {#on_dismiss}, fired exactly once, and only
    # when no action button was chosen. There is deliberately no keep-open knob:
    # a dialog that leads somewhere opens the next dialog from its callback.
    #
    # Keys: Left/Right (and Tab) move between the buttons, Enter/Space press the
    # focused one, and each button answers to its underlined mnemonic letter
    # (see {#button}). The message scrolls without taking focus —
    # {BODY_SCROLL_KEYS} are handed to it from anywhere in the dialog. Focus
    # opens on the first button; Shift+Tab reaches the message, a tab stop of
    # its own.
    #
    # The dialog sizes itself from what it owns — caption, message, buttons —
    # capped at half the screen ({#measured_width}, {#measure_rows}), re-measured
    # when any of them changes.
    #
    # There is deliberately no content slot: the body is prose ({#message=}
    # takes a component for the rare rich body, but the dialog then cannot
    # measure it). A dialog collecting *input* is not a confirm dialog — build a
    # `Dialog.new(caption, content: your_layout)`. See `design/decisions.md`
    # `D_confirm_window` for the API rationale.
    class ConfirmDialog < Dialog
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
      # unconditionally the dismiss key ({Dialog#handle_key?} claims it),
      # and `g`/`G` scroll the message ({BODY_SCROLL_KEYS}).
      # @return [Array<String>]
      RESERVED_MNEMONICS = %w[q g].freeze

      # Border rows plus the body-to-buttons spacing plus the button row — what
      # {#measure_rows} adds to the wrapped message rows.
      # @return [Integer]
      HEIGHT_CHROME = 4
      # Border columns plus the body padding — what {#measured_width} adds to the
      # widest message line, and subtracts to find the wrap width.
      # @return [Integer]
      WIDTH_CHROME = 4
      private_constant :HEIGHT_CHROME, :WIDTH_CHROME

      # @param caption [String, StyledString, nil] the border title, coerced the
      #   same way {HasCaption#caption=} coerces it.
      def initialize(caption = nil)
        @_chosen = false
        @_message = nil
        # Insertion-ordered; identity-keyed so equal captions stay two buttons.
        @_actions = {}.compare_by_identity
        @_mnemonics = {}
        super(caption)
        @_body_slot = Slot.new
        @_button_row = Layout::Horizontal.new(spacing: 2)
        @_box = Layout::Vertical.new(spacing: 1, padding: Layout::Insets[left: 1, right: 1])
        @_box.add(@_body_slot, Layout::Expand[1])
        @_box.add(@_button_row, Layout::Fixed[1], cross: Layout::Fixed[0], align: :center)
        self.content = @_box
        on_close { notice_dismissed(_1) }
      end

      # What {#on_dismiss} fires.
      #
      # @!attribute [r] source
      #   @return [ConfirmDialog] the dialog that was dismissed.
      DismissEvent = Data.define(:source) { include Tuile::Event }

      # @!method on_dismiss
      #   Fired with a {DismissEvent} when the dialog is dismissed — ESC, `q`, an
      #   outside click, {#close}, or a {#button} declared without a block. Fires
      #   at most once per {#open}: never when an action button was chosen, and
      #   never when {Screen#close} tears the dialog down with the app.
      #   @return [Listeners]
      listener :on_dismiss

      # @return [String, StyledString, Component, nil] whatever {#message=} was
      #   given — set a `String`, read that `String` back. The component
      #   rendering it is derived, never returned.
      def message = @_message

      # Also re-measures the dialog: the caption participates in the width.
      # @param new_caption [String, StyledString, nil]
      # @return [void]
      def caption=(new_caption)
        super
        reposition
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
        @_message = value
        @_body_slot.content = occupant
        # The body sits in an Expand row its box never measures, so the notice
        # stops inside; this dialog's own answer reads the message.
        invalidate_rows
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
      # the dialog, case-insensitively — is underlined in the caption. Any case
      # is accepted, and the underline prefers the exact case given, so the case
      # picks which occurrence is cued (`"Save As"` with `"A"` underlines the
      # *As*), exactly as on {MenuBar#add_item}. The default `:auto` derives the
      # caption's first letter (cueing it as displayed) and is best-effort:
      # silently skipped when that letter is reserved, taken, or unusable. An
      # explicit letter is a promise and raises when it cannot be kept.
      #
      # Declare buttons before {#open}: adding one to an open dialog re-measures
      # it, but momentarily bounces focus off the button row.
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
        # The cue keeps the case the caller (or the caption) wrote, so `:auto`
        # underlines "Discard"'s leading D rather than its trailing d, and an
        # explicit letter picks its occurrence by case as on MenuBar; `letter`
        # is the downcased matching key.
        cue = mnemonic == :auto ? styled.to_s.grapheme_clusters.first : mnemonic
        btn = Button.new(letter ? underline_mnemonic(styled, cue) : styled)
        btn.on_click { activate(btn) }
        @_actions[btn] = action
        @_mnemonics[letter] = btn unless letter.nil?
        @_button_row.add(btn, Layout::Fixed[btn.caption.display_width + 4])
        recenter_button_row
        reposition
        btn
      end

      # Opens the dialog, {#measured_width} wide and {#measure_rows} tall. ESC,
      # `q` and an outside click dismiss it (firing {#on_dismiss}), as does
      # {#close}; every button closes it too.
      # @param placement [Overlay::Placement] see {Overlay#open}.
      # @raise [Tuile::Error] if this dialog is already open.
      # @return [self]
      def open(placement = default_placement)
        raise Tuile::Error, "#{inspect} is already open" if open?

        @_chosen = false
        super
      end

      # The width this dialog wants: wide enough for the caption, the widest
      # message line and the button row, capped at half of `reference`. Read
      # only from what the dialog owns, so a {Component} assigned to
      # {#message=} yields the full half width. The height is {#measure_rows} at
      # this width, under the same half-screen cap.
      # @param reference [Size] the screen size to cap against.
      # @return [Integer]
      def measured_width(reference = screen.size)
        cap = Fraction::HALF.resolve(reference).width
        return cap if @_message.is_a?(Component)

        widest = message_text.lines.map(&:display_width).max || 0
        [[caption.display_width + 2, button_row_width + WIDTH_CHROME, widest + WIDTH_CHROME].max, cap].min
      end

      # The border, the message wrapped at `width` less the border and padding,
      # and the button row. `nil` for a {Component} message, which the dialog
      # does not own and so does not measure.
      # @param width [Integer]
      # @return [Integer, nil]
      def measure_rows(width)
        return nil if @_message.is_a?(Component)

        styled = message_text
        rows = styled.empty? ? 0 : styled.wrap([width - WIDTH_CHROME, 1].max).size
        rows + HEIGHT_CHROME
      end

      # A {Dialog::ShrinkToContent} half-screen-tall box at {#measured_width},
      # rebuilt on every layout pass so a message change and a SIGWINCH both
      # re-fit the dialog. {#declared_size} is ignored.
      # @param screen_size [Size]
      # @return [Size]
      def declared_size_in(screen_size)
        box = Size.new(measured_width(screen_size), Fraction::HALF.resolve(screen_size).height)
        resolve_declaration(ShrinkToContent[box], screen_size)
      end

      # Focus lands on the first button rather than cascading into the message
      # body, which sits before the button row in the tree. `super` is reached
      # only when there is no button to take it: {HasContent#handle_focus} *is*
      # the cascade this override exists to skip.
      # @return [void]
      def handle_focus
        first = @_actions.keys.first
        if first.nil?
          super
        else
          screen.focused = first
        end
      end

      # Handles the dialog-wide keys: Left/Right move between the buttons,
      # {BODY_SCROLL_KEYS} are hand-fed to the message body, and a mnemonic
      # letter presses its button; the rest goes to {Dialog#handle_key?}. Reached
      # by bubbling — the focused button or body sees the key first, so a
      # focused body consumes its own scroll keys before this runs.
      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_key?(key)
        handled =
          case key
          when Keys::LEFT_ARROW then focus_button_step(-1)
          when Keys::RIGHT_ARROW then focus_button_step(1)
          when *BODY_SCROLL_KEYS then @_body_slot.content&.handle_key?(key) || false
          else press_mnemonic(key)
          end
        handled || super
      end

      # Opens an acknowledgement dialog: a message and one button, whose press
      # is the dismissal. The button exists for discoverability — ESC and `q`
      # close too, but Tuile advertises no keys anywhere, and the button is
      # clickable.
      # @param caption [String, StyledString, nil] the border title.
      # @param message [String, StyledString, Component, nil] see {#message=}.
      # @param button [String, StyledString] the button label.
      # @return [ConfirmDialog] the opened dialog.
      def self.alert(caption, message, button: "OK")
        dialog = new(caption)
        dialog.message = message
        dialog.button(button)
        dialog.open
      end

      # Opens a two-button question: the block is the action, the cancel button
      # (with ESC, `q` and an outside click) is the dismissal.
      #
      #   Component::ConfirmDialog.confirm("Delete Report Q4?", "This cannot be undone.",
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
      # @return [ConfirmDialog] the opened dialog.
      def self.confirm(caption, message, confirm: "Confirm", cancel: "Cancel", on_dismiss: nil, &action)
        raise ArgumentError, "block required" unless action

        dialog = new(caption)
        dialog.message = message
        dialog.button(confirm, &action)
        dialog.button(cancel)
        dialog.on_dismiss << on_dismiss if on_dismiss
        dialog.open
      end

      # {.confirm} with Yes/No labels — the other canonical phrasing.
      # @param caption [String, StyledString, nil] the border title.
      # @param message [String, StyledString, Component, nil] see {#message=}.
      # @param on_dismiss [Proc, nil] see {#on_dismiss}.
      # @yield the action, fired on Yes after the dialog closes.
      # @raise [ArgumentError] without a block.
      # @return [ConfirmDialog] the opened dialog.
      def self.yes_no(caption, message, on_dismiss: nil, &action)
        confirm(caption, message, confirm: "Yes", cancel: "No", on_dismiss:, &action)
      end

      private

      # The chosen-button path, in the settled order: mark chosen, close (whose
      # on_close then skips the dismissal), fire the callback last so it sees
      # the dialog already gone — a callback opening a follow-up dialog gets
      # clean focus-repair state.
      # @param btn [Button]
      # @return [void]
      def activate(btn)
        action = @_actions[btn]
        @_chosen = true
        close
        action.nil? ? fire_dismissed : action.call
      end

      # The {#on_close} listener: fires {#on_dismiss} unless a button was chosen
      # or the screen is being torn down — which makes ESC, `q`, an outside
      # click, {#close} and a direct {Screen#remove_overlay} one event, fired
      # exactly once. Teardown is no dismissal: the app is ending, and a
      # callback would run mid-unmount.
      # @param event [Overlay::CloseEvent]
      # @return [void]
      def notice_dismissed(event)
        return if @_chosen || event.reason == :teardown

        @_chosen = true
        fire_dismissed
      end

      # @return [void]
      def fire_dismissed = on_dismiss.fire(DismissEvent.new(source: self))

      # @param key [String]
      # @return [Boolean] whether `key` is a mnemonic, whose button it pressed.
      def press_mnemonic(key)
        target = @_mnemonics[key.downcase]
        return false if target.nil?

        activate(target)
        true
      end

      # @param delta [Integer] -1 or 1.
      # @return [Boolean] false when focus is not on a button (the key bubbles on).
      def focus_button_step(delta)
        buttons = @_actions.keys
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
        raise ArgumentError, "duplicate mnemonic #{down.inspect}" if @_mnemonics.key?(down)

        down
      end

      # @param caption [StyledString]
      # @return [String, nil]
      def derive_mnemonic(caption)
        letter = caption.to_s.grapheme_clusters.first&.downcase
        return nil if letter.nil? || letter == " "
        return nil unless Keys.printable?(letter) && StyledString.plain(letter).display_width == 1
        return nil if RESERVED_MNEMONICS.include?(letter) || @_mnemonics.key?(letter)

        letter
      end

      # {StyledString#slice} counts **columns** while a caption search yields a
      # **character** index, so the prefix is measured, never counted (the
      # {MenuBar::Item} cue, duplicated per `D_float_field`'s shallow-shell rule).
      # @param caption [StyledString]
      # @param cue [String] the letter in the case it was given in — exact case
      #   first, so the case picks which occurrence is underlined.
      # @return [StyledString]
      def underline_mnemonic(caption, cue)
        text = caption.to_s
        index = text.index(cue) || text.downcase.index(cue.downcase)
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
        @_box.remove(@_button_row)
        @_box.add(@_button_row, Layout::Fixed[1], cross: Layout::Fixed[button_row_width], align: :center)
      end

      # @return [StyledString] a text {#message}, empty when there is none.
      def message_text = @_message.nil? ? StyledString::EMPTY : StyledString.parse(@_message)

      # @return [Integer] columns of the button row at its natural width.
      def button_row_width
        widths = @_actions.keys.map { _1.caption.display_width + 4 }
        widths.sum + (@_button_row.spacing * [widths.size - 1, 0].max)
      end
    end
  end
end
