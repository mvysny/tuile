# frozen_string_literal: true

module Tuile
  describe Component::ConfirmWindow do
    before { Screen.fake }
    after { Screen.close }

    # Drive through the real dispatcher (Screen#handle_key): keys reach the
    # dialog by bubbling from the focused button or body, exactly as in a
    # running app.
    def press(key) = Screen.instance.send(:handle_key, key)

    # @return [Component::TextView, nil] the dialog's message body.
    def body_view(dialog)
      view = nil
      dialog.on_tree { |c| view ||= c if c.is_a?(Component::TextView) }
      view
    end

    def build_dialog
      dialog = Component::ConfirmWindow.new("Delete Report Q4?")
      dialog.message = "This cannot be undone."
      dialog.button("Delete") { @deleted = true }
      dialog.button("Cancel")
      dialog.on_dismiss = -> { @dismissed = (@dismissed || 0) + 1 }
      dialog
    end

    it "is a Window" do
      assert Component::ConfirmWindow.new("foo").is_a?(Component::Window)
    end

    describe "#open" do
      it "opens a popup sized from caption, message and buttons, capped at half the screen" do
        popup = build_dialog.open
        assert popup.open?
        # widest: the button row "[ Delete ]  [ Cancel ]" (22) + 4 chrome; the
        # 22-column message line wraps to one row.
        assert_equal Size.new(26, 5), popup.rect.size
      end

      it "focuses the first button" do
        build_dialog.open
        assert_equal "Delete", Screen.instance.focused.caption.to_s
      end

      it "paints caption, message and buttons" do
        popup = build_dialog.open
        Screen.instance.repaint
        rows = Screen.instance.buffer.region_text(popup.rect)
        assert rows[0].include?("Delete Report Q4?")
        assert rows[1].include?("This cannot be undone.")
        assert rows[3].include?("[ Delete ]  [ Cancel ]")
      end

      it "raises when already open" do
        dialog = build_dialog
        dialog.open
        assert_raises(Tuile::Error) { dialog.open }
      end

      it "can reopen after closing" do
        dialog = build_dialog
        first = dialog.open
        first.close
        second = dialog.open
        assert second.open?
        assert_nil first.content
      end
    end

    describe "activation" do
      it "Enter on the focused button closes, then fires the block, and never on_dismiss" do
        dialog = build_dialog
        popup = dialog.open
        open_at_fire = nil
        dialog.button("Probe") { open_at_fire = popup.open? }
        press("p")
        assert_equal false, open_at_fire
        assert_nil @dismissed
      end

      it "fires the action button's block" do
        build_dialog.open
        press(Keys::ENTER)
        assert @deleted
        assert_nil @dismissed
      end

      it "a button without a block dismisses, exactly once" do
        popup = build_dialog.open
        press(Keys::RIGHT_ARROW) # focus Cancel
        press(Keys::ENTER)
        assert_equal 1, @dismissed
        assert !popup.open?
        assert_nil @deleted
      end

      it "a left click on a button activates it" do
        popup = build_dialog.open
        Screen.instance.repaint
        delete_rect = Screen.instance.focused.rect
        Screen.instance.pane.handle_mouse(MouseEvent.new(:left, delete_rect.left, delete_rect.top))
        assert @deleted
        assert !popup.open?
      end
    end

    describe "dismissal" do
      %W[q #{Keys::ESC}].each do |key|
        it "fires on_dismiss exactly once on #{key.inspect}" do
          popup = build_dialog.open
          press(key)
          assert !popup.open?
          assert_equal 1, @dismissed
          assert_nil @deleted
        end
      end

      it "#close dismisses programmatically" do
        dialog = build_dialog
        popup = dialog.open
        dialog.close
        assert !popup.open?
        assert_equal 1, @dismissed
      end
    end

    describe "mnemonics" do
      it "a mnemonic letter activates its button from the default focus" do
        build_dialog.open
        press("c") # Cancel — focus sits on Delete
        assert_equal 1, @dismissed
      end

      it "matches case-insensitively" do
        build_dialog.open
        press("D")
        assert @deleted
      end

      it "underlines the derived letter in the caption" do
        dialog = Component::ConfirmWindow.new
        btn = dialog.button("Delete")
        expected = StyledString.plain("D").with_underline + StyledString.plain("elete")
        assert_equal expected, btn.caption
      end

      it ":auto cues the first letter as displayed, not its downcased twin later on" do
        # "Discard" holds both a D and a d; an exact-case hunt for the downcased
        # derivation used to underline the trailing d.
        btn = Component::ConfirmWindow.new.button("Discard")
        expected = StyledString.plain("D").with_underline + StyledString.plain("iscard")
        assert_equal expected, btn.caption
      end

      it "an explicit letter picks its underlined occurrence by case, matching either case" do
        dialog = Component::ConfirmWindow.new
        btn = dialog.button("Save As", mnemonic: "A") { @saved_as = true }
        expected = StyledString.plain("Save ") + StyledString.plain("A").with_underline +
                   StyledString.plain("s")
        assert_equal expected, btn.caption
        dialog.open
        press("a")
        assert @saved_as
      end

      it ":auto silently skips a taken letter" do
        dialog = Component::ConfirmWindow.new
        dialog.button("Confirm") { @confirmed = true }
        dialog.button("Cancel")
        dialog.open
        press("c")
        assert @confirmed # the first c wins; Cancel got no mnemonic
      end

      it ":auto silently skips q, which keeps dismissing" do
        dialog = Component::ConfirmWindow.new
        dialog.button("Quit") { @quit = true }
        dialog.on_dismiss = -> { @dismissed = true }
        popup = dialog.open
        press("q")
        assert_nil @quit
        assert @dismissed
        assert !popup.open?
      end

      %w[q g G].each do |letter|
        it "raises on the explicit reserved letter #{letter.inspect}" do
          dialog = Component::ConfirmWindow.new
          e = assert_raises(ArgumentError) { dialog.button("Go", mnemonic: letter) }
          assert e.message.include?("reserved")
        end
      end

      it "raises on an explicit space" do
        assert_raises(ArgumentError) { Component::ConfirmWindow.new.button("x", mnemonic: " ") }
      end

      it "raises on an explicit duplicate" do
        dialog = Component::ConfirmWindow.new
        dialog.button("Save")
        assert_raises(ArgumentError) { dialog.button("Skip", mnemonic: "s") }
      end

      it "raises on a non-printable explicit mnemonic" do
        assert_raises(ArgumentError) { Component::ConfirmWindow.new.button("x", mnemonic: Keys::TAB) }
      end

      it "mnemonic: nil declares none" do
        dialog = Component::ConfirmWindow.new
        btn = dialog.button("Save", mnemonic: nil)
        assert_equal StyledString.plain("Save"), btn.caption
      end
    end

    describe "message body" do
      def build_tall_dialog
        dialog = Component::ConfirmWindow.new("Long")
        dialog.message = (1..40).map { "line #{_1}" }.join("\n")
        dialog.button("OK") { @ok = true }
        dialog
      end

      it "scrolls via hand-fed keys while a button keeps focus" do
        dialog = build_tall_dialog
        dialog.open
        view = body_view(dialog)
        press(Keys::DOWN_ARROW)
        assert_equal 1, view.scroll_top_row
        assert_equal "OK", Screen.instance.focused.caption.to_s
        press("G")
        assert view.scroll_top_row > 1
        press("g")
        assert_equal 0, view.scroll_top_row
      end

      it "does not hand-feed the vi j/k aliases — they stay mnemonic material" do
        dialog = build_tall_dialog
        dialog.open
        view = body_view(dialog)
        press("j")
        assert_equal 0, view.scroll_top_row
      end

      it "is a tab stop reached by Shift+Tab" do
        dialog = build_tall_dialog
        dialog.open
        press(Keys::SHIFT_TAB)
        assert_equal body_view(dialog), Screen.instance.focused
      end
    end

    describe "#message" do
      it "returns what was assigned, for each accepted kind" do
        dialog = Component::ConfirmWindow.new
        dialog.message = "plain"
        assert_equal "plain", dialog.message
        styled = StyledString.plain("styled")
        dialog.message = styled
        assert_equal styled, dialog.message
        label = Component::Label.new("rich")
        dialog.message = label
        assert_equal label, dialog.message
        assert_equal dialog, label.root
        dialog.message = nil
        assert_nil dialog.message
      end

      it "raises TypeError on anything else" do
        assert_raises(TypeError) { Component::ConfirmWindow.new.message = 42 }
      end
    end

    describe "#measured_size" do
      it "caps at half the screen" do
        dialog = Component::ConfirmWindow.new("x")
        dialog.message = "word " * 2000
        dialog.button("OK")
        assert_equal Size.new(80, 25), dialog.measured_size(Size.new(160, 50))
      end

      it "takes the full half-screen box for a Component message it cannot measure" do
        dialog = Component::ConfirmWindow.new("x")
        dialog.message = Component::Label.new("injected")
        assert_equal Size.new(80, 25), dialog.measured_size(Size.new(160, 50))
      end

      it "re-measures an open popup when the message changes" do
        dialog = Component::ConfirmWindow.new("x")
        dialog.message = "short"
        dialog.button("OK")
        popup = dialog.open
        narrow = popup.rect.width
        dialog.message = "a considerably longer single message line"
        assert popup.rect.width > narrow
      end
    end

    describe "button-row focus" do
      it "Left/Right move between buttons, wrapping" do
        dialog = Component::ConfirmWindow.new
        dialog.button("One") { @one = true }
        dialog.button("Two")
        dialog.open
        press(Keys::RIGHT_ARROW)
        assert_equal "Two", Screen.instance.focused.caption.to_s
        press(Keys::RIGHT_ARROW)
        assert_equal "One", Screen.instance.focused.caption.to_s
        press(Keys::LEFT_ARROW)
        assert_equal "Two", Screen.instance.focused.caption.to_s
      end
    end

    describe "tiled" do
      it "buttons fire with nothing to close" do
        dialog = build_dialog
        Screen.instance.content = dialog
        Screen.instance.focused = dialog
        press(Keys::ENTER)
        assert @deleted
        press("c")
        assert_equal 1, @dismissed
      end
    end

    describe ".alert" do
      it "opens one acknowledgement button whose press dismisses" do
        popup = Component::ConfirmWindow.alert("Oops", "It broke.")
        assert popup.open?
        press(Keys::ENTER)
        assert !popup.open?
      end
    end

    describe ".confirm" do
      it "requires a block" do
        assert_raises(ArgumentError) { Component::ConfirmWindow.confirm("x", "y") }
      end

      it "wires the action, the cancel and on_dismiss" do
        popup = Component::ConfirmWindow.confirm("Delete?", "Gone forever.",
                                                 confirm: "Delete",
                                                 on_dismiss: -> { @dismissed = true }) { @deleted = true }
        press("d")
        assert @deleted
        assert !popup.open?
        assert_nil @dismissed
      end
    end

    describe ".yes_no" do
      it "labels Yes/No with y/n mnemonics" do
        Component::ConfirmWindow.yes_no("Sure?", "Really?",
                                        on_dismiss: -> { @dismissed = true }) { @yes = true }
        press("n")
        assert @dismissed
        assert_nil @yes
      end
    end
  end
end
