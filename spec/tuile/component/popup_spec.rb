# frozen_string_literal: true

module Tuile
  describe Component::Popup do
    before { Screen.fake }
    after { Screen.close }

    def list_of(lines)
      Component::List.new.tap { _1.lines = lines }
    end

    it "smokes" do
      p = Component::Popup.new
      p.open
      assert p.open?
      p.close
      assert !p.open?
    end

    it "accepts content via the constructor" do
      list = list_of(%w[a b c])
      p = Component::Popup.new(content: list)
      assert_equal list, p.content
    end

    it "closes on q" do
      p = Component::Popup.new
      p.open
      p.handle_key "q"
      assert !p.open?
    end

    it "closes on ESC" do
      p = Component::Popup.new
      p.open
      p.handle_key Keys::ESC
      assert !p.open?
    end

    it "returns false for unhandled keys" do
      p = Component::Popup.new
      p.open
      assert !p.handle_key("x")
    end

    it "draws nothing on repaint" do
      p = Component::Popup.new(content: list_of(["hello"]))
      p.open
      Screen.instance.prints.clear
      p.repaint
      assert_equal [], Screen.instance.prints
    end

    it "lays out content to fill the entire popup rect" do
      list = list_of(["hello"])
      p = Component::Popup.new(content: list)
      p.open
      assert_equal p.rect, list.rect
    end
  end

  describe Component::Popup, "content=" do
    before { Screen.fake }
    after { Screen.close }

    def list_of(lines)
      Component::List.new.tap { _1.lines = lines }
    end

    it "sets rect width based on content_size" do
      p = Component::Popup.new
      # List#content_size = (longest_line + 2, line_count). "hello" is 5 → 7 wide.
      p.content = list_of(["hello"])
      assert_equal 7, p.rect.width
    end

    it "sets rect height based on content count" do
      p = Component::Popup.new
      p.content = list_of(%w[a b c])
      assert_equal 3, p.rect.height
    end

    it "clamps height to max_height" do
      p = Component::Popup.new
      p.content = list_of(Array.new(20, "x"))
      assert_equal 12, p.rect.height
    end

    it "re-centers when open" do
      p = Component::Popup.new
      p.open
      p.content = list_of(["hello"])
      assert_equal 76, p.rect.left # (160 - 7) / 2 = 76
      assert_equal 24, p.rect.top  # (50 - 1) / 2 = 24
    end

    it "does not center when closed" do
      p = Component::Popup.new
      p.content = list_of(["hello"])
      assert_equal(-1, p.rect.left)
      assert_equal(-1, p.rect.top)
    end
  end

  describe Component::Popup, "#center" do
    before { Screen.fake }
    after { Screen.close }

    it "centers the popup on screen" do
      p = Component::Popup.new(content: Component::List.new.tap { _1.lines = ["hello"] })
      p.center
      assert_equal 76, p.rect.left
      assert_equal 24, p.rect.top
    end
  end

  describe Component::Popup, "#keyboard_hint" do
    before { Screen.fake }
    after { Screen.close }

    it "is just 'q Close' when content has no hint" do
      p = Component::Popup.new(content: Component::List.new.tap { _1.lines = ["a"] })
      assert_equal "q Close", Rainbow.uncolor(p.keyboard_hint)
    end

    it "appends the wrapped content's hint" do
      window = Class.new(Component::Window) { def keyboard_hint = "h help" }.new
      window.content = Component::List.new.tap { _1.lines = ["a"] }
      p = Component::Popup.new(content: window)
      assert_equal "q Close  h help", Rainbow.uncolor(p.keyboard_hint)
    end
  end

  describe Component::Popup, "wrapping a Window" do
    before { Screen.fake }
    after { Screen.close }

    it "lets the window draw its border over the popup rect" do
      window = Component::Window.new("Hi")
      window.content = Component::List.new.tap { _1.lines = ["one", "two"] }
      p = Component::Popup.new(content: window)
      p.open
      # window's rect should equal popup's rect — popup is borderless
      assert_equal p.rect, window.rect
    end
  end
end
