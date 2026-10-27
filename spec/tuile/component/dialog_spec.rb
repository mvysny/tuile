# frozen_string_literal: true

module Tuile
  describe Component::Dialog do
    before { Screen.fake } # 160x50
    after { Screen.close }

    def list_of(lines)
      Component::List.new.tap { _1.lines = lines }
    end

    it "smokes" do
      p = Component::Dialog.new
      p.open
      assert p.open?
      p.close
      assert !p.open?
    end

    it "close is a no-op when the popup is not open" do
      p = Component::Dialog.new
      p.close # never opened
      assert !p.open?

      p.open
      p.close
      p.close # already closed
      assert !p.open?
    end

    it "accepts content via the constructor" do
      list = list_of(%w[a b c])
      p = Component::Dialog.new(content: list)
      assert_equal list, p.content
    end

    it "closes on q" do
      p = Component::Dialog.new
      p.open
      p.handle_key? "q"
      assert !p.open?
    end

    it "closes on ESC" do
      p = Component::Dialog.new
      p.open
      p.handle_key? Keys::ESC
      assert !p.open?
    end

    context "with close_on_key: false" do
      it "is close_on_key? by default, and the flag is writable" do
        assert Component::Dialog.new.close_on_key?
        p = Component::Dialog.new(close_on_key: false)
        assert !p.close_on_key?
        p.close_on_key = true
        assert p.close_on_key?
      end

      # Swallowed, not passed on: an unhandled q/ESC would stop the loop
      # (D_quit_key), so FakeScreen#key reporting it handled is what keeps the
      # app running beneath the popup.
      it "swallows q and ESC without closing" do
        p = Component::Dialog.new(content: list_of(%w[a b]), close_on_key: false)
        p.open
        assert Screen.instance.key("q")
        assert Screen.instance.key(Keys::ESC)
        assert p.open?
      end

      it "still closes from code" do
        p = Component::Dialog.new(close_on_key: false)
        p.open
        p.close
        assert !p.open?
      end

      it "closes on q again once re-enabled" do
        p = Component::Dialog.new(close_on_key: false)
        p.open
        p.close_on_key = true
        assert Screen.instance.key("q")
        assert !p.open?
      end
    end

    it "returns false for unhandled keys" do
      p = Component::Dialog.new
      p.open
      assert !p.handle_key?("x")
    end

    it "draws nothing on repaint" do
      p = Component::Dialog.new(content: list_of(["hello"]))
      p.open
      Screen.instance.prints.clear
      repaint(p)
      assert_equal [], Screen.instance.prints
    end

    it "lays out content inside the border" do
      list = list_of(["hello"])
      p = Component::Dialog.new(content: list)
      p.open
      assert_equal Rect.new(1, 1, p.width - 2, p.height - 2), list.rect
    end

    it "content inside a closed popup does not invalidate or paint" do
      list = Component::List.new
      p = Component::Dialog.new(content: list)
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

  describe Component::Dialog, "border" do
    before { Screen.fake }
    after { Screen.close }

    # @return [Component::Dialog] an open 12x4 dialog around a two-row list.
    def open_dialog(caption = "Hi")
      list = Component::List.new.tap { _1.lines = %w[one two] }
      Component::Dialog.new(caption, content: list, declared_size: Size.new(12, 4)).open
    end

    def rows(dialog)
      Screen.instance.repaint
      Screen.instance.buffer.region_text(dialog.absolute_rect)
    end

    it "frames the content, the caption set into the top edge" do
      assert_equal ["┌Hi────────┐", "│ one      │", "│ two      │", "└──────────┘"], rows(open_dialog)
    end

    it "embeds footer_text into the bottom edge" do
      dialog = open_dialog
      dialog.footer_text = "q close"
      assert_equal "└q close───┘", rows(dialog).last
    end

    it "lights the border while focus is inside, and dims it under a stacked dialog" do
      lower = open_dialog
      Screen.instance.repaint
      lit = Screen.instance.theme.active_border_color
      assert_equal lit, Screen.instance.buffer.cell(lower.absolute_rect.left, lower.absolute_rect.top + 1).style.fg

      Component::Dialog.new("Top", declared_size: Size.new(4, 3)).open
      Screen.instance.repaint
      refute_equal lit, Screen.instance.buffer.cell(lower.absolute_rect.left, lower.absolute_rect.top + 1).style.fg
    end

    it "hands the right border column to the content's scrollbar" do
      dialog = open_dialog
      dialog.scrollbar = true
      dialog.flush_layout
      assert_equal Rect.new(1, 1, 11, 2), dialog.content.rect
    end

    it "refuses scrollbar= on content that has no scrollbar" do
      dialog = Component::Dialog.new(content: Component::Label.new("x"))
      assert_raises(Tuile::Error) { dialog.scrollbar = true }
    end
  end

  describe Component::Dialog, "footer_text" do
    before { Screen.fake }
    after { Screen.close }

    it "is empty by default" do
      assert Component::Dialog.new.footer_text.empty?
    end

    it "is taken by the constructor" do
      assert_equal StyledString.plain("q to close"), Component::Dialog.new(footer_text: "q to close").footer_text
    end

    it "coerces a String to a StyledString" do
      w = Component::Dialog.new
      w.footer_text = "gpt-4"
      assert_equal StyledString.plain("gpt-4"), w.footer_text
    end

    it "accepts a StyledString" do
      w = Component::Dialog.new
      ss = StyledString.styled("gpt-4", fg: :red)
      w.footer_text = ss
      assert_equal ss, w.footer_text
    end

    it "clears back to empty when set to nil" do
      w = Component::Dialog.new
      w.footer_text = "gpt-4"
      w.footer_text = nil
      assert w.footer_text.empty?
    end

    it "invalidates on change" do
      w = Component::Dialog.new
      w.open
      Screen.instance.invalidated_clear
      w.footer_text = "gpt-4"
      assert Screen.instance.invalidated?(w)
    end

    it "is a no-op when set to the same text" do
      w = Component::Dialog.new
      w.footer_text = "gpt-4"
      Screen.instance.invalidated_clear
      w.footer_text = "gpt-4"
      assert !Screen.instance.invalidated?(w)
    end

    it "embeds into the bottom border with dashes filling the remainder" do
      w = Component::Dialog.new
      w.open(Component::Overlay::At[Rect.new(0, 0, 20, 10)])
      w.footer_text = "hi"
      painted = Testing.paint(w)
      # inner width 18: "hi" + 16 dashes
      assert_equal "└hi#{"─" * 16}┘", painted.text.last
    end

    it "clips footer_text to the inner width" do
      w = Component::Dialog.new
      w.open(Component::Overlay::At[Rect.new(0, 0, 6, 4)])
      w.footer_text = "far-too-long"
      painted = Testing.paint(w)
      # inner width 4
      assert_equal "└far-┘", painted.text.last
    end
  end

  describe Component::Dialog, "size" do
    before { Screen.fake } # 160x50
    after { Screen.close }

    it "defaults to Fraction::HALF (half the screen, centered)" do
      p = Component::Dialog.new
      p.open
      # HALF of 160x50 = 80x25; centered at ((160-80)/2, (50-25)/2) = (40, 12).
      assert_equal Rect.new(40, 12, 80, 25), p.rect
      assert_equal Fraction::HALF, p.declared_size
    end

    it "does not size itself to its content (content fills the box)" do
      # A bare TextField reports Size::ZERO; the popup stays HALF regardless.
      p = Component::Dialog.new(content: Component::TextField.new)
      p.open
      assert_equal 80, p.rect.width
      assert_equal 25, p.rect.height
    end

    it "resolves Fraction::FULL to the whole screen" do
      p = Component::Dialog.new(declared_size: Fraction::FULL)
      p.open
      assert_equal Rect.new(0, 0, 160, 50), p.rect
    end

    it "resolves an arbitrary Fraction proportionally" do
      p = Component::Dialog.new(declared_size: Fraction.new(0.8, 0.5))
      p.open
      # 0.8*160 = 128 wide, 0.5*50 = 25 tall; centered at ((160-128)/2, 12).
      assert_equal Rect.new(16, 12, 128, 25), p.rect
    end

    it "applies an absolute Size, centered" do
      p = Component::Dialog.new(declared_size: Size.new(50, 12))
      p.open
      assert_equal Rect.new(55, 19, 50, 12), p.rect
    end

    it "clamps an oversized absolute Size to the screen" do
      p = Component::Dialog.new(declared_size: Size.new(300, 100))
      p.open
      assert_equal Rect.new(0, 0, 160, 50), p.rect
    end

    it "size= re-sizes and re-centers an open popup" do
      p = Component::Dialog.new
      p.open
      p.declared_size = Size.new(20, 6)
      # centered: ((160-20)/2, (50-6)/2) = (70, 22).
      p.flush_layout
      assert_equal Rect.new(70, 22, 20, 6), p.rect
    end

    it "size= accepts a Fraction" do
      p = Component::Dialog.new
      p.open
      p.declared_size = Fraction::FULL
      p.flush_layout
      assert_equal Rect.new(0, 0, 160, 50), p.rect
    end

    it "returns self from open, so construct-and-mount is one expression" do
      p = Component::Dialog.new(declared_size: Fraction::FULL).open
      assert_equal Rect.new(0, 0, 160, 50), p.rect
      assert p.open?
    end

    it "has no class-level open factory — it could only ever build a bare Dialog" do
      assert !Component::Dialog.respond_to?(:open)
      assert !Component::ListDropdown.respond_to?(:open)
    end

    it "re-resolves a Fraction size against the screen on layout (resize tracking)" do
      p = Component::Dialog.new # Fraction::HALF
      p.open
      assert_equal Rect.new(40, 12, 80, 25), p.rect

      # Simulate a SIGWINCH-driven reposition: shrink the screen, re-lay out.
      Screen.instance.instance_variable_set(:@_size, Size.new(100, 30))
      Screen.instance.resize_terminal(100, 30)
      # HALF of 100x30 = 50x15; centered at ((100-50)/2, (30-15)/2) = (25, 7).
      p.flush_layout
      assert_equal Rect.new(25, 7, 50, 15), p.rect
    end
  end

  describe Component::Dialog::ShrinkToContent do
    before { Screen.fake } # 160x50
    after { Screen.close }

    # Answers `rows` and records every width it was asked at.
    let(:content) do
      klass = Class.new(Component::Label) do
        attr_accessor :rows
        attr_reader :asked

        def measure_rows(width)
          (@asked ||= []) << width
          rows
        end
      end
      klass.new.tap { _1.rows = 7 }
    end

    def shrink(box) = Component::Dialog::ShrinkToContent[box]

    def open_shrunk(box) = Component::Dialog.new(content:, declared_size: shrink(box)).open

    it "shrinks a Fraction box to the content's rows at its inner width plus the border, centered" do
      p = open_shrunk(Fraction::HALF)
      assert_equal 78, content.asked.last
      # 7 rows + 2 border rows; ((160-80)/2, (50-9)/2) = (40, 20).
      assert_equal Rect.new(40, 20, 80, 9), p.rect
    end

    it "shrinks a Size box" do
      assert_equal Size.new(60, 9), open_shrunk(Size.new(60, 20)).rect.size
    end

    it "caps the rows at the box's height" do
      content.rows = 40
      p = open_shrunk(Fraction::HALF)
      assert_equal 25, p.rect.height
      p.declared_size = shrink(Size.new(60, 12))
      p.flush_layout
      assert_equal Size.new(60, 12), p.rect.size
      p.declared_size = shrink(Size.new(300, 100))
      p.flush_layout
      assert_equal Size.new(160, 42), p.rect.size
    end

    it "floors a zero answer at one interior row" do
      content.rows = 0
      assert_equal 3, open_shrunk(Fraction::HALF).rect.height
    end

    it "takes the whole box when the content answers nil, or there is none" do
      content.rows = nil
      assert_equal Size.new(60, 20), open_shrunk(Size.new(60, 20)).rect.size
      assert_equal Size.new(80, 25), Component::Dialog.new(declared_size: shrink(Fraction::HALF)).open.rect.size
    end

    it "re-asks on reposition, which is the content's notice" do
      p = open_shrunk(Fraction::HALF)
      content.rows = 12
      p.flush_layout
      assert_equal 9, p.rect.height
      p.reposition
      p.flush_layout
      assert_equal 14, p.rect.height
    end

    it "re-asks at the new width on resize" do
      p = open_shrunk(Fraction::HALF)
      Screen.instance.resize_terminal(100, 30)
      p.flush_layout
      assert_equal 48, content.asked.last
      assert_equal Size.new(50, 9), p.rect.size
    end

    it "measures the content at the width the border leaves, plus the border's rows" do
      assert_equal 9, Component::Dialog.new(content:).measure_rows(40)
      assert_equal 38, content.asked.last
      assert_nil Component::Dialog.new.measure_rows(40)
    end

    it "raises on a box that is neither a Size nor a Fraction" do
      [nil, 0.5, [60, 20], shrink(Fraction::HALF)].each do |bad|
        assert_raises(ArgumentError) { shrink(bad) }
      end
      assert_equal Fraction::HALF, shrink(Fraction::HALF).box
    end
  end

  describe Component::Dialog, "placement" do
    before { Screen.fake }
    after { Screen.close }

    it "opens centered by default" do
      p = Component::Dialog.new(declared_size: Size.new(40, 10)).open
      assert_equal Component::Overlay::Centered[], p.placement
      # ((160-40)/2, (50-10)/2) = (60, 20).
      assert_equal Rect.new(60, 20, 40, 10), p.rect
    end

    # A hand-placed popup's placement *is* its rect, so re-running the pane's
    # pass — a second popup opening — leaves it where it was put.
    it "stays hand-placed when a second popup opens" do
      first = Component::Dialog.new.open(Component::Overlay::At[Rect.new(3, 4, 20, 5)])
      Component::Dialog.new.open
      first.flush_layout
      assert_equal Rect.new(3, 4, 20, 5), first.rect
    end
  end

  describe Component::Dialog, "full-repaint escalation" do
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
      p = Component::Dialog.new # HALF, (40,12,80,25)
      p.open
      Screen.instance.invalidated_clear

      p.declared_size = Size.new(10, 5) # smaller, recentered; new rect can't cover old
      p.flush_layout
      assert Screen.instance.invalidated?(tiled)
    end

    it "uses the popup-only fast path when an open popup only grows" do
      p = Component::Dialog.new(declared_size: Size.new(10, 5))
      p.open
      Screen.instance.invalidated_clear

      p.declared_size = Fraction::FULL # grows to cover the whole screen (covers old)
      p.flush_layout
      assert Screen.instance.invalidated?(p)
      refute Screen.instance.invalidated?(tiled)
    end

    it "does not request a full repaint when a closed popup is resized" do
      p = Component::Dialog.new
      p.open
      p.close
      Screen.instance.invalidated_clear

      p.declared_size = Size.new(10, 5) # resizing a detached popup touches nothing on screen
      refute Screen.instance.invalidated?(tiled)
    end
  end

  describe Component::Dialog, "the modal contract" do
    before { Screen.fake }
    after { Screen.close }

    it "is modal" do
      assert Component::Dialog.new.modal?
    end

    # Unlike a bare Overlay: ScreenPane#add_popup focuses a popup on open, and
    # focus repair falls back to it when its subtree holds no tab stop.
    it "is focusable" do
      assert Component::Dialog.new.focusable?
    end

    # ScreenPane#add_popup focuses the popup, and the handle_focus cascade then
    # forwards into its content — so what is pinned here is that focus lands
    # *inside* the popup, not that it rests on the wrapper.
    it "grabs focus when opened" do
      p = Component::Dialog.new(content: Component::List.new)
      p.open
      assert p.active?
      assert_equal p, Screen.instance.focused.root.popups.first
    end
  end

  describe Component::Dialog, "close_on_outside_click" do
    before { Screen.fake }
    after { Screen.close }

    it "passes close_on_outside_click through to Overlay" do
      assert Component::Dialog.new.close_on_outside_click?
      assert !Component::Dialog.new(close_on_outside_click: false).close_on_outside_click?
    end
  end
end
