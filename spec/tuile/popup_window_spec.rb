# frozen_string_literal: true

module Tuile
  describe PopupWindow do
    before { Screen.fake }
    after { Screen.close }

    it "smokes" do
      w = PopupWindow.new("foo")
      w.open
      assert w.open?
      w.close
      assert !w.open?
    end

    it "closes on q" do
      w = PopupWindow.new("foo")
      w.open
      w.handle_key "q"
      assert !w.open?
    end

    it "closes on ESC" do
      w = PopupWindow.new("foo")
      w.open
      w.handle_key Keys::ESC
      assert !w.open?
    end

    it "returns false for unhandled keys" do
      w = PopupWindow.new("foo")
      w.open
      assert !w.handle_key("x")
    end
  end

  describe PopupWindow, "content=" do
    before { Screen.fake }
    after { Screen.close }

    it "sets rect width based on longest content line" do
      w = PopupWindow.new("foo")
      w.content = ["hello"] # 5 chars + 4 border/padding = 9
      assert_equal 9, w.rect.width
    end

    it "sets rect height based on content count" do
      w = PopupWindow.new("foo")
      w.content = %w[a b c] # 3 lines + 2 border = 5
      assert_equal 5, w.rect.height
    end

    it "clamps height to max_height" do
      w = PopupWindow.new("foo")
      w.content = Array.new(20, "x") # 20 lines, clamped to 12
      assert_equal 12, w.rect.height
    end

    it "does not enable cursor when content fits within max_height" do
      w = PopupWindow.new("foo")
      w.content = Array.new(12, "x") # 12 == max_height, not >
      assert w.content.cursor.is_a?(Component::List::Cursor::None)
    end

    it "enables cursor when content exceeds max_height" do
      w = PopupWindow.new("foo")
      w.content = Array.new(13, "x") # 13 > max_height (12)
      assert !w.content.cursor.is_a?(Component::List::Cursor::None)
    end

    it "re-centers window when open" do
      w = PopupWindow.new("foo")
      w.open
      w.content = ["hello"]
      assert_equal 75, w.rect.left # (160 - 9) / 2
      assert_equal 23, w.rect.top  # (50 - 3) / 2
    end

    it "does not center window when closed" do
      w = PopupWindow.new("foo")
      w.content = ["hello"]
      assert_equal(-1, w.rect.left)
      assert_equal(-1, w.rect.top)
    end
  end

  describe PopupWindow, "#center" do
    before { Screen.fake }
    after { Screen.close }

    it "centers the window on screen" do
      w = PopupWindow.new("foo")
      w.content = ["hello"]
      w.center
      assert_equal 75, w.rect.left # (160 - 9) / 2
      assert_equal 23, w.rect.top  # (50 - 3) / 2
    end
  end
end
