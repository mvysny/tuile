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

    it "returns self from open, so construct-and-mount is one expression" do
      p = Component::Popup.new(size: Fraction::FULL).open
      assert_equal Rect.new(0, 0, 160, 50), p.rect
      assert p.open?
    end

    it "has no class-level open factory — it could only ever build a bare Popup" do
      assert !Component::Popup.respond_to?(:open)
      assert !Component::ListDropdown.respond_to?(:open)
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
    # A shrinking/moving popup vacates cells that the popup-only fast path in
    # Screen#repaint can't clear (nothing paints underneath a popup), so the
    # whole scene must repaint. `tiled` is a component in the tiled layer, so
    # its invalidation is a proxy for "full repaint requested" — it has to be
    # installed *before* the popup moves, hence the before block.
    attr_reader :tiled

    before do
      Screen.fake
      @tiled = Component::Label.new
      Screen.instance.content = @tiled
    end
    after { Screen.close }

    it "fully repaints the scene when an open popup shrinks" do
      p = Component::Popup.new # HALF, (40,12,80,25)
      p.open
      Screen.instance.invalidated_clear

      p.size = Size.new(10, 5) # smaller, recentered; new rect can't cover old
      assert Screen.instance.invalidated?(tiled)
    end

    it "uses the popup-only fast path when an open popup only grows" do
      p = Component::Popup.new(size: Size.new(10, 5))
      p.open
      Screen.instance.invalidated_clear

      p.size = Fraction::FULL # grows to cover the whole screen (covers old)
      assert Screen.instance.invalidated?(p)
      refute Screen.instance.invalidated?(tiled)
    end

    it "does not request a full repaint when a closed popup is resized" do
      p = Component::Popup.new
      p.open
      p.close
      Screen.instance.invalidated_clear

      p.size = Size.new(10, 5) # resizing a detached popup touches nothing on screen
      refute Screen.instance.invalidated?(tiled)
    end
  end

  describe Component::Popup, "the modal contract" do
    before { Screen.fake }
    after { Screen.close }

    it "is modal" do
      assert Component::Popup.new.modal?
    end

    # Unlike a bare Overlay: ScreenPane#add_popup focuses a popup on open, and
    # focus repair falls back to it when its subtree holds no tab stop.
    it "is focusable" do
      assert Component::Popup.new.focusable?
    end

    # ScreenPane#add_popup focuses the popup, and the on_focus cascade then
    # forwards into its content — so what is pinned here is that focus lands
    # *inside* the popup, not that it rests on the wrapper.
    it "grabs focus when opened" do
      p = Component::Popup.new(content: Component::List.new)
      p.open
      assert p.active?
      assert_equal p, Screen.instance.focused.root.popups.first
    end

    it "recenters when repositioned, ignoring a caller-assigned top-left" do
      p = Component::Popup.new(size: Fraction::HALF)
      p.open
      p.rect = p.rect.at(Point.new(12, 7))

      p.reposition
      assert_equal 40, p.rect.left # re-centered, ignoring the manual move
      assert_equal 12, p.rect.top
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
    it "passes close_on_outside_click through to Overlay" do
      assert Component::Popup.new.close_on_outside_click?
      assert !Component::Popup.new(close_on_outside_click: false).close_on_outside_click?
    end
  end
end
