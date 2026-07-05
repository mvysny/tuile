# frozen_string_literal: true

module Tuile
  describe Component::Popup do
    before { Screen.fake } # 160x50
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
  end

  describe Component::Popup, "size" do
    before { Screen.fake } # 160x50
    after { Screen.close }

    it "defaults to Fraction::HALF (half the screen, centered)" do
      p = Component::Popup.new
      p.open
      # HALF of 160x50 = 80x25; centered at ((160-80)/2, (50-25)/2) = (40, 12).
      assert_equal Rect.new(40, 12, 80, 25), p.rect
      assert_equal Fraction::HALF, p.size
    end

    it "does not size itself to its content (content fills the box)" do
      # A bare TextField reports Size::ZERO; the popup stays HALF regardless.
      p = Component::Popup.new(content: Component::TextField.new)
      p.open
      assert_equal 80, p.rect.width
      assert_equal 25, p.rect.height
    end

    it "resolves Fraction::FULL to the whole screen" do
      p = Component::Popup.new(size: Fraction::FULL)
      p.open
      assert_equal Rect.new(0, 0, 160, 50), p.rect
    end

    it "resolves an arbitrary Fraction proportionally" do
      p = Component::Popup.new(size: Fraction.new(0.8, 0.5))
      p.open
      # 0.8*160 = 128 wide, 0.5*50 = 25 tall; centered at ((160-128)/2, 12).
      assert_equal Rect.new(16, 12, 128, 25), p.rect
    end

    it "applies an absolute Size, centered" do
      p = Component::Popup.new(size: Size.new(50, 12))
      p.open
      assert_equal Rect.new(55, 19, 50, 12), p.rect
    end

    it "clamps an oversized absolute Size to the screen" do
      p = Component::Popup.new(size: Size.new(300, 100))
      p.open
      assert_equal Rect.new(0, 0, 160, 50), p.rect
    end

    it "size= re-sizes and re-centers an open popup" do
      p = Component::Popup.new
      p.open
      p.size = Size.new(20, 6)
      # centered: ((160-20)/2, (50-6)/2) = (70, 22).
      assert_equal Rect.new(70, 22, 20, 6), p.rect
    end

    it "size= accepts a Fraction" do
      p = Component::Popup.new
      p.open
      p.size = Fraction::FULL
      assert_equal Rect.new(0, 0, 160, 50), p.rect
    end

    it "self.open takes a size: kwarg" do
      p = Component::Popup.open(size: Fraction::FULL)
      assert_equal Rect.new(0, 0, 160, 50), p.rect
    end

    it "re-resolves a Fraction size against the screen on layout (resize tracking)" do
      p = Component::Popup.new # Fraction::HALF
      p.open
      assert_equal Rect.new(40, 12, 80, 25), p.rect

      # Simulate a SIGWINCH-driven reposition: shrink the screen, re-lay out.
      Screen.instance.instance_variable_set(:@size, Size.new(100, 30))
      Screen.instance.pane.rect = Rect.new(0, 0, 100, 30)
      # HALF of 100x30 = 50x15; centered at ((100-50)/2, (30-15)/2) = (25, 7).
      assert_equal Rect.new(25, 7, 50, 15), p.rect
    end
  end

  describe Component::Popup, "#center" do
    before { Screen.fake }
    after { Screen.close }

    it "centers the popup on screen, preserving its size" do
      p = Component::Popup.new(size: Size.new(40, 10))
      p.center
      # ((160-40)/2, (50-10)/2) = (60, 20).
      assert_equal Rect.new(60, 20, 40, 10), p.rect
    end
  end

  describe Component::Popup, "full-repaint escalation" do
    before { Screen.fake }
    after { Screen.close }

    # A shrinking/moving popup vacates cells that the popup-only fast path in
    # Screen#repaint can't clear (nothing paints underneath a popup), so the
    # whole scene must repaint. The status bar is a tiled component, so its
    # invalidation is a proxy for "full repaint requested".
    def status_bar = Screen.instance.pane.status_bar

    it "fully repaints the scene when an open popup shrinks" do
      p = Component::Popup.new # HALF, (40,12,80,25)
      p.open
      Screen.instance.invalidated_clear

      p.size = Size.new(10, 5) # smaller, recentered; new rect can't cover old
      assert Screen.instance.invalidated?(status_bar)
    end

    it "uses the popup-only fast path when an open popup only grows" do
      p = Component::Popup.new(size: Size.new(10, 5))
      p.open
      Screen.instance.invalidated_clear

      p.size = Fraction::FULL # grows to cover the whole screen (covers old)
      assert Screen.instance.invalidated?(p)
      refute Screen.instance.invalidated?(status_bar)
    end

    it "fully repaints when an open non-modal overlay moves clear of its previous cells" do
      p = Component::Popup.new(content: Component::List.new.tap { _1.lines = ["hi"] },
                               modal: false, size: Size.new(6, 1))
      p.open
      Screen.instance.invalidated_clear

      old = p.rect
      p.rect = old.at(Point.new(old.left + old.width + 5, old.top))
      assert Screen.instance.invalidated?(status_bar)
    end

    it "does not request a full repaint when a closed popup is resized" do
      p = Component::Popup.new
      p.open
      p.close
      Screen.instance.invalidated_clear

      p.size = Size.new(10, 5) # resizing a detached popup touches nothing on screen
      refute Screen.instance.invalidated?(status_bar)
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

    it "keeps its caller-assigned top-left when repositioned, size following the screen" do
      overlay = Component::Popup.new(content: list_of(%w[a b]), modal: false, size: Fraction::HALF)
      overlay.open
      overlay.rect = overlay.rect.at(Point.new(12, 7)) # caller positions it

      overlay.reposition
      assert_equal 12, overlay.rect.left  # position preserved (non-modal)
      assert_equal 7, overlay.rect.top
      assert_equal 80, overlay.rect.width # HALF of 160
      assert_equal 25, overlay.rect.height
    end

    it "recenters a modal popup when repositioned (contrast)" do
      modal = Component::Popup.new(size: Fraction::HALF) # modal: true
      modal.open
      modal.rect = modal.rect.at(Point.new(12, 7))

      modal.reposition
      assert_equal 40, modal.rect.left # re-centered, ignoring the manual move
      assert_equal 12, modal.rect.top
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
