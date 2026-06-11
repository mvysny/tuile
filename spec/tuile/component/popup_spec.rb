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

    it "close is a no-op when the popup is not open" do
      p = Component::Popup.new
      p.close # never opened
      assert !p.open?

      p.open
      p.close
      p.close # already closed
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

    it "resizes from current content when reopened" do
      list = Component::List.new
      p = Component::Popup.new(content: list)
      p.open
      assert_equal 0, p.rect.width
      assert_equal 0, p.rect.height
      p.close

      list.lines = %w[alpha beta gamma]
      p.open
      # List#content_size = (longest + 2, line_count). "alpha"/"gamma" = 5 → 7 wide, 3 lines.
      assert_equal 7, p.rect.width
      assert_equal 3, p.rect.height
    end

    it "content inside a closed popup does not invalidate or paint" do
      list = Component::List.new
      p = Component::Popup.new(content: list)
      p.open
      p.close
      assert !list.attached?
      Screen.instance.invalidated_clear
      Screen.instance.prints.clear

      list.lines = %w[a b c]
      assert !Screen.instance.invalidated?(list)
      Screen.instance.repaint
      assert_equal [], Screen.instance.prints
    end

    it "re-sizes and re-centers when the content's content_size changes while open" do
      list = Component::List.new
      p = Component::Popup.new(content: list)
      p.open

      list.lines = %w[alpha beta gamma]
      # List#content_size = (longest + 2, line_count) = (7, 3), recentered.
      assert_equal Rect.new(76, 23, 7, 3), p.rect
    end

    it "re-sizes when a nested Window's content grows (the change bubbles up)" do
      w = Component::Window.new
      list = Component::List.new
      w.content = list
      p = Component::Popup.new(content: w)
      p.open
      assert_equal 2, p.rect.width # bare border

      list.add_line "hello"
      # list (7, 1) → window (9, 3) → popup follows
      assert_equal 9, p.rect.width
      assert_equal 3, p.rect.height
    end

    it "does not re-size when a nested Window's footer grows (footer is decoration)" do
      w = Component::Window.new
      w.content = list_of(["hi"]) # (4, 1) → window (6, 3)
      f = Component::Label.new
      w.footer = f
      p = Component::Popup.new(content: w)
      p.open
      assert_equal 6, p.rect.width

      f.text = "a-footer-longer-than-the-window"
      # Footer changes don't alter the window's content_size, so nothing
      # bubbles to the popup.
      assert_equal 6, p.rect.width
    end

    # A shrinking/moving popup vacates cells that the popup-only fast path in
    # Screen#repaint can't clear (nothing paints underneath a popup), so the
    # whole scene must repaint. The status bar is a tiled component, so its
    # invalidation is a proxy for "full repaint requested".
    def status_bar = Screen.instance.pane.status_bar

    it "fully repaints the scene when an open popup shrinks" do
      list = list_of(%w[alpha beta gamma]) # (7, 3)
      p = Component::Popup.new(content: list)
      p.open
      Screen.instance.invalidated_clear

      list.lines = %w[a] # (3, 1) — smaller, recentered; new rect can't cover old
      assert Screen.instance.invalidated?(status_bar)
    end

    it "uses the popup-only fast path when an open popup only grows" do
      list = list_of(%w[a]) # (3, 1)
      p = Component::Popup.new(content: list)
      p.open
      Screen.instance.invalidated_clear

      list.lines = %w[alpha beta gamma] # (7, 3) — grows, new rect covers old
      assert Screen.instance.invalidated?(p)
      refute Screen.instance.invalidated?(status_bar)
    end

    it "fully repaints when an open popup moves clear of its previous cells" do
      p = Component::Popup.new(content: list_of(["hello"]))
      p.open
      Screen.instance.invalidated_clear

      old = p.rect
      p.rect = old.at(Point.new(old.left + old.width + 5, old.top))
      assert Screen.instance.invalidated?(status_bar)
    end

    it "does not request a full repaint when a closed popup is resized" do
      list = list_of(%w[alpha beta gamma])
      p = Component::Popup.new(content: list)
      p.open
      p.close
      Screen.instance.invalidated_clear

      list.lines = %w[a] # resizing a detached popup touches nothing on screen
      refute Screen.instance.invalidated?(status_bar)
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

    it "floors height at min_height when content is shorter" do
      klass = Class.new(Component::Popup) { def min_height = 20 }
      p = klass.new
      p.content = list_of(%w[a b c]) # 3 lines of content
      assert_equal 20, p.rect.height
    end

    it "does not floor height above min_height when content is taller" do
      klass = Class.new(Component::Popup) do
        def min_height = 5
        def max_height = 30
      end
      p = klass.new
      p.content = list_of(Array.new(12, "x"))
      assert_equal 12, p.rect.height
    end

    it "caps min_height at the 4/5-of-screen ceiling" do
      # Screen.fake is 160x50; 4/5 height = 40.
      klass = Class.new(Component::Popup) { def min_height = 1000 }
      p = klass.new
      p.content = list_of(%w[a])
      assert_equal 40, p.rect.height
    end

    it "floors height at the content's popup_min_height advice" do
      content = list_of(%w[a b c])
      content.define_singleton_method(:popup_min_height) { 20 }
      p = Component::Popup.new(content: content)
      assert_equal 20, p.rect.height
    end

    it "grows height to the content's popup_max_height advice" do
      content = list_of(Array.new(30, "x"))
      content.define_singleton_method(:popup_max_height) { 25 }
      p = Component::Popup.new(content: content)
      assert_equal 25, p.rect.height
    end

    it "a subclass min_height override wins over the content advice" do
      content = list_of(%w[a b c])
      content.define_singleton_method(:popup_min_height) { 20 }
      klass = Class.new(Component::Popup) { def min_height = 8 }
      p = klass.new(content: content)
      assert_equal 8, p.rect.height
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
      assert_equal(0, p.rect.left)
      assert_equal(0, p.rect.top)
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

  describe Component::Popup, "non-modal overlay" do
    before { Screen.fake }
    after { Screen.close }

    def list_of(lines)
      Component::List.new.tap { _1.lines = lines }
    end

    it "is modal by default" do
      assert Component::Popup.new.modal?
    end

    it "is non-modal when constructed with modal: false" do
      assert !Component::Popup.new(modal: false).modal?
    end

    it "does not grab focus or center when opened" do
      content = Component::Layout::Absolute.new
      field = Component::TextField.new
      field.rect = Rect.new(0, 0, 10, 1)
      content.add(field)
      Screen.instance.content = content
      Screen.instance.focused = field

      Component::Popup.new(content: list_of(%w[a b]), modal: false).open
      assert_equal field, Screen.instance.focused # focus untouched
    end

    it "keeps its caller-assigned top-left when content resizes while open" do
      list = list_of(%w[a b])
      overlay = Component::Popup.new(content: list, modal: false)
      overlay.open
      overlay.rect = Rect.new(12, 7, overlay.rect.width, overlay.rect.height)

      list.lines = %w[aaaa bbbb cccc dddd]            # taller + wider content
      assert_equal 12, overlay.rect.left
      assert_equal 7, overlay.rect.top                # position preserved; only size grew
      assert_equal 4, overlay.rect.height             # resized to the new content
    end

    it "recenters a modal popup on the same content change (contrast)" do
      list = list_of(%w[a b])
      modal = Component::Popup.new(content: list) # modal: true
      modal.open
      centered_top = modal.rect.top

      list.lines = %w[aaaa bbbb cccc dddd]
      refute_equal centered_top, modal.rect.top # re-centered for the new height
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
      window.content = Component::List.new.tap { _1.lines = %w[one two] }
      p = Component::Popup.new(content: window)
      p.open
      # window's rect should equal popup's rect — popup is borderless
      assert_equal p.rect, window.rect
    end
  end
end
