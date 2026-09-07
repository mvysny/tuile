# frozen_string_literal: true

module Tuile
  describe Component::PickerWindow do
    before { Screen.fake }
    after { Screen.close }

    it "is a Window" do
      picker = Component::PickerWindow.new("foo", [%w[a all]]) {}
      assert picker.is_a?(Component::Window)
    end

    it "renders option rows into its inner list" do
      picker = Component::PickerWindow.new("foo", [%w[a all]]) {}
      assert picker.content.is_a?(Component::List)
      assert_equal Component::PickerWindow::Option.new("a", StyledString.plain("all")),
                   picker.content.items.first
      picker.rect = Rect.new(0, 0, 20, 3)
      picker.content.repaint
      assert_equal "a all", Screen.instance.buffer.region_text(picker.content.rect).first.strip
    end

    # The picker recommends no ink of its own: a plain caption inherits the
    # terminal's foreground, and the app colors one by handing in a
    # StyledString (or the ANSI String Theme#fg returns).
    describe "caption styling" do
      # A row is `" <key> <caption>"`: List's one-column gutter, the key, a
      # separator, then the caption.
      key_column = 1
      caption_column = 3

      # @return [Tuile::Buffer::Cell] the cell `column` cells into row `row`.
      def paint(options, column:, row: 0)
        picker = Component::PickerWindow.new("foo", options) {}
        picker.rect = Rect.new(0, 0, 20, 4)
        picker.content.repaint
        rect = picker.content.rect
        Screen.instance.buffer.cell(rect.left + column, rect.top + row)
      end

      it "leaves a String caption in the terminal's own foreground" do
        assert_equal "a", paint([%w[a all]], column: caption_column).grapheme
        assert_nil paint([%w[a all]], column: caption_column).style.fg
      end

      it "keeps a StyledString caption's own color, per option" do
        options = [["a", StyledString.styled("all", fg: Color::GREEN)],
                   ["b", StyledString.plain("bare")]]
        assert_equal Color::GREEN, paint(options, column: caption_column).style.fg
        assert_nil paint(options, column: caption_column, row: 1).style.fg
        # The key stays unstyled either way — only the caption is the app's.
        assert_nil paint(options, column: key_column).style.fg
      end

      it "parses an ANSI-coded String caption, as Theme#fg hands back" do
        theme = Theme::DARK.with(custom: { hint: Color::GREEN })
        assert_equal Color::GREEN, paint([["a", theme.fg(:hint, "all")]], column: caption_column).style.fg
      end
    end

    describe ".open" do
      it "opens as a popup wrapping a PickerWindow" do
        popup = Component::PickerWindow.open("foo", [%w[a all]]) {}
        assert popup.is_a?(Component::Popup)
        assert popup.content.is_a?(Component::PickerWindow)
        assert popup.open?
        popup.close
      end

      # Drive through the real dispatcher (Screen#handle_key): opening the
      # popup focuses the inner List, and keys reach the picker by capture +
      # bubble, exactly as in a running app.
      def press(key) = Screen.instance.send(:handle_key, key)

      it "doesn't call block when closed via q" do
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { raise "should not be called" }
        press("q")
        assert !popup.open?
      end

      it "selects first option on enter" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = _1 }
        press(Keys::ENTER)
        assert_equal "a", selected
        assert !popup.open?
      end

      it "selects correct option when its key is pressed" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = _1 }
        press("a")
        assert_equal "a", selected
        assert !popup.open?
      end

      it "does nothing if an unlisted key is pressed" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = _1 }
        press("b")
        assert_nil selected
        assert popup.open?
      end
    end
  end
end
