# frozen_string_literal: true

module Tuile
  describe Component::PasswordField do
    before { Screen.fake }
    after { Screen.close }

    def field(width: 10, text: "", active: false)
      f = Component::PasswordField.new
      f.rect = Rect.new(0, 0, width, 1)
      f.text = text
      f.active = active if active
      f
    end

    it "defaults to a masked field with an asterisk" do
      f = Component::PasswordField.new
      assert_equal "*", f.mask_char
      assert !f.revealed?
    end

    it "keeps the plaintext in text/value while painting only mask glyphs" do
      f = field
      "s3cret".each_char { |c| f.handle_key(c) }
      assert_equal "s3cret", f.text
      assert_equal "s3cret", f.value
      f.repaint
      assert_equal ["******    "], Screen.instance.buffer.region_text(f.rect)
    end

    it "is empty like any text field" do
      assert field.empty?
      assert !field(text: "x").empty?
    end

    context "repaint" do
      it "paints the mask on the inactive well" do
        f = field(text: "abc")
        f.repaint
        assert_equal [Screen.instance.theme.input_bg("***       ")],
                     Screen.instance.buffer.region_ansi(f.rect)
      end

      it "uses the active well when active" do
        f = field(text: "abc", active: true)
        f.repaint
        assert_equal [Screen.instance.theme.active_bg("***       ")],
                     Screen.instance.buffer.region_ansi(f.rect)
      end

      it "paints an all-spaces row when empty" do
        f = field
        f.repaint
        assert_equal [" " * 10], Screen.instance.buffer.region_text(f.rect)
      end
    end

    context "mask_char=" do
      it "repaints with the new glyph" do
        f = field(text: "abc")
        f.mask_char = "•"
        f.repaint
        assert_equal ["•••       "], Screen.instance.buffer.region_text(f.rect)
      end

      it "invalidates on change" do
        f = field(text: "abc")
        Screen.instance.content = f
        Screen.instance.invalidated_clear
        f.mask_char = "#"
        assert Screen.instance.invalidated?(f)
      end

      it "is a no-op when unchanged" do
        f = field(text: "abc")
        Screen.instance.content = f
        Screen.instance.invalidated_clear
        f.mask_char = "*"
        assert !Screen.instance.invalidated?(f)
      end

      it "rejects a non-String" do
        assert_raises(TypeError) { field.mask_char = 42 }
      end

      it "rejects a wide glyph, which would break the column axis" do
        assert_raises(ArgumentError) { field.mask_char = "日" }
      end

      it "rejects a multi-cluster string, which would break the character count" do
        assert_raises(ArgumentError) { field.mask_char = "**" }
      end

      it "rejects an empty string" do
        assert_raises(ArgumentError) { field.mask_char = "" }
      end

      it "accepts a combining cluster that measures one column" do
        f = field(text: "ab")
        f.mask_char = "é"
        f.repaint
        assert_equal ["éé        "], Screen.instance.buffer.region_text(f.rect)
      end
    end

    context "revealed" do
      it "shows the plaintext" do
        f = field(text: "s3cret")
        f.revealed = true
        f.repaint
        assert_equal ["s3cret    "], Screen.instance.buffer.region_text(f.rect)
      end

      it "re-masks when set back to false" do
        f = field(text: "s3cret")
        f.revealed = true
        f.revealed = false
        f.repaint
        assert_equal ["******    "], Screen.instance.buffer.region_text(f.rect)
      end

      it "coerces to true/false" do
        f = field
        f.revealed = "yes"
        assert_equal true, f.revealed
      end

      it "invalidates on change" do
        f = field(text: "abc")
        Screen.instance.content = f
        Screen.instance.invalidated_clear
        f.revealed = true
        assert Screen.instance.invalidated?(f)
      end

      it "is a no-op when unchanged" do
        f = field(text: "abc")
        Screen.instance.content = f
        Screen.instance.invalidated_clear
        f.revealed = false
        assert !Screen.instance.invalidated?(f)
      end
    end

    # Every example here fails if the mask is painted without the column
    # measurements following it — the caret, the scroll window and the click
    # resolution all read display_text.
    context "the mask's own column axis" do
      it "puts the cursor after the last mask glyph, not the last text column" do
        f = field(width: 20, text: "日本語")
        f.caret = 3
        assert_equal Point.new(3, 0), f.cursor_position
        f.revealed = true
        assert_equal Point.new(6, 0), f.cursor_position
      end

      it "does not scroll while the mask fits, though the plaintext would not" do
        f = field(width: 10, text: "日本語日本語")
        f.caret = 6
        assert_equal 0, f.send(:left_column)
        f.revealed = true
        assert_equal 4, f.send(:left_column) # 3 would open on 本's right half
      end

      it "resolves a click to the mask glyph clicked" do
        f = field(width: 20, text: "日本語", active: true) # already focused: no click-to-focus detour
        f.handle_mouse(MouseEvent.new(:left, 2, 0))
        assert_equal 2, f.caret
      end

      it "paints one mask glyph per character, not per grapheme cluster" do
        f = field(width: 10, text: "é") # decomposed "é": 2 chars, 1 column
        f.repaint
        assert_equal ["**        "], Screen.instance.buffer.region_text(f.rect)
      end

      it "holds the one-display-character-per-character contract" do
        ["", "abc", "日本語", "é", "a日é́x", "👍🏽"].each do |text|
          f = field(width: 20, text: text)
          assert_equal f.text.length, f.send(:display_text).length, text.inspect
        end
      end

      it "scrolls the mask to follow the caret" do
        f = field(width: 6, text: "hello world")
        f.caret = 11
        assert_equal 6, f.send(:left_column)
        assert_equal Point.new(5, 0), f.cursor_position
        f.repaint
        assert_equal ["***** "], Screen.instance.buffer.region_text(f.rect)
      end
    end

    # Every display index is a boundary here (one mask per character), so a
    # boundary-locked text caret always names a real mask column — but an edit
    # still steps by a *text* cluster, so a 2-char cluster takes 2 masks with it.
    context "grapheme clusters" do
      it "removes every mask glyph of one cluster on BACKSPACE" do
        f = field(width: 10, text: "abe\u{0301}", active: true)
        f.caret = 4
        f.repaint
        assert_equal ["****      "], Screen.instance.buffer.region_text(f.rect)
        f.handle_key(Keys::BACKSPACE)
        f.repaint
        assert_equal "ab", f.text
        assert_equal ["**        "], Screen.instance.buffer.region_text(f.rect)
      end

      it "keeps the cursor on a mask column after the caret snaps" do
        f = field(width: 10, text: "abe\u{0301}", active: true)
        f.caret = 3 # inside the cluster
        assert_equal 4, f.caret
        assert_equal Point.new(4, 0), f.cursor_position
      end
    end

    context "word jumps" do
      it "ctrl+left goes to the start while masked, hiding the space positions" do
        f = field(width: 20, text: "hello world")
        f.caret = 11
        assert f.handle_key(Keys::CTRL_LEFT_ARROW)
        assert_equal 0, f.caret
      end

      it "ctrl+right goes to the end while masked" do
        f = field(width: 20, text: "hello world")
        assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
        assert_equal 11, f.caret
      end

      it "resumes word jumping when revealed" do
        f = field(width: 20, text: "hello world")
        f.revealed = true
        assert f.handle_key(Keys::CTRL_RIGHT_ARROW)
        assert_equal 6, f.caret
        assert f.handle_key(Keys::CTRL_LEFT_ARROW)
        assert_equal 0, f.caret
      end
    end

    context "placeholder" do
      # Inherited unchanged, and correct as-is: the mask only ever applies to
      # buffer content, and a field showing its hint has none.
      it "paints the hint unmasked while empty, then masks the typed value" do
        f = Component::PasswordField.new
        f.rect = Rect.new(0, 0, 12, 1)
        f.placeholder = "password"
        f.repaint
        assert_equal ["password    "], Screen.instance.buffer.region_text(f.rect)
        assert_equal Screen.instance.theme.placeholder_color, Screen.instance.buffer.cell(0, 0).style.fg

        f.text = "hunter2"
        f.repaint
        assert_equal ["*******     "], Screen.instance.buffer.region_text(f.rect)
      end
    end
  end
end
