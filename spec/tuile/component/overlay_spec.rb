# frozen_string_literal: true

module Tuile
  describe Component::Overlay do
    before { Screen.fake } # 160x50
    after { Screen.close }

    def list_of(lines)
      Component::List.new.tap { _1.lines = lines }
    end

    it "smokes" do
      o = Component::Overlay.new
      o.open
      assert o.open?
      o.close
      assert !o.open?
    end

    it "close is a no-op when the overlay is not open" do
      o = Component::Overlay.new
      o.close # never opened
      assert !o.open?

      o.open
      o.close
      o.close # already closed
      assert !o.open?
    end

    it "returns self from open, so construct-and-mount is one expression" do
      o = Component::Overlay.new.open
      assert o.open?
    end

    it "has no class-level open factory — it could only ever build a bare Overlay" do
      assert !Component::Overlay.respond_to?(:open)
      assert !Component::Popup.respond_to?(:open)
      assert !Component::ListDropdown.respond_to?(:open)
    end

    it "accepts content via the constructor" do
      list = list_of(%w[a b c])
      assert_equal list, Component::Overlay.new(content: list).content
    end

    it "lays out content to fill the entire overlay rect" do
      list = list_of(["hello"])
      o = Component::Overlay.new(content: list)
      o.open
      o.rect = Rect.new(3, 4, 20, 2)
      assert_equal o.rect, list.rect
    end

    it "draws nothing on repaint" do
      o = Component::Overlay.new(content: list_of(["hello"]))
      o.open
      Screen.instance.prints.clear
      o.repaint
      assert_equal [], Screen.instance.prints
    end

    it "content inside a closed overlay does not invalidate or paint" do
      list = Component::List.new
      o = Component::Overlay.new(content: list)
      o.open
      o.close
      assert !list.attached?
      Screen.instance.invalidated_clear
      Screen.instance.prints.clear

      list.lines = %w[a b c]
      assert !Screen.instance.invalidated?(list)
      Screen.instance.repaint
      assert_equal [], Screen.instance.prints
    end

    context "the non-modal contract" do
      # All three are load-bearing rather than incidental: an overlay that took
      # focus would land it outside the key-dispatch scope, where ScreenPane
      # delivers to nobody and every keystroke goes dead until Tab recovers.
      # Inherited by every subclass that isn't a Popup, which is what stops each
      # one having to remember to opt out.
      it "is not modal" do
        assert !Component::Overlay.new.modal?
      end

      it "is not focusable" do
        assert !Component::Overlay.new.focusable?
      end

      it "is not a tab stop" do
        assert !Component::Overlay.new.tab_stop?
      end

      it "does not grab focus or center when opened" do
        content = Component::Layout::Absolute.new
        field = Component::TextField.new
        field.rect = Rect.new(0, 0, 10, 1)
        content.add(field)
        Screen.instance.content = content
        Screen.instance.focused = field

        Component::Overlay.new(content: list_of(%w[a b])).open
        assert_equal field, Screen.instance.focused # focus untouched
      end
    end

    context "#reposition" do
      it "is a no-op — the rect is whatever the caller assigned" do
        o = Component::Overlay.new(content: list_of(%w[a b]))
        o.open
        o.rect = Rect.new(12, 7, 20, 2) # caller positions it

        o.reposition
        assert_equal Rect.new(12, 7, 20, 2), o.rect
      end

      it "survives the screen's layout pass untouched" do
        o = Component::Overlay.new(content: list_of(%w[a b]))
        o.open
        o.rect = Rect.new(12, 7, 20, 2)

        Screen.instance.pane.rect = Rect.new(0, 0, 160, 50) # drives reposition
        assert_equal Rect.new(12, 7, 20, 2), o.rect
      end
    end

    context "full-repaint escalation" do
      attr_reader :tiled

      before do
        @tiled = Component::Label.new
        Screen.instance.content = @tiled
      end

      it "fully repaints when an open overlay moves clear of its previous cells" do
        o = Component::Overlay.new(content: list_of(["hi"]))
        o.open
        o.rect = Rect.new(0, 0, 6, 1)
        Screen.instance.invalidated_clear

        old = o.rect
        o.rect = old.at(Point.new(old.left + old.width + 5, old.top))
        assert Screen.instance.invalidated?(tiled)
      end

      it "does not request a full repaint when a closed overlay is moved" do
        o = Component::Overlay.new
        o.open
        o.rect = Rect.new(0, 0, 6, 1)
        o.close
        Screen.instance.invalidated_clear

        o.rect = Rect.new(40, 20, 3, 1)
        refute Screen.instance.invalidated?(tiled)
      end
    end

    context "close_on_outside_click" do
      it "defaults to true" do
        assert Component::Overlay.new.close_on_outside_click?
      end

      it "is settable via the constructor and the writer" do
        o = Component::Overlay.new(close_on_outside_click: false)
        assert !o.close_on_outside_click?

        o.close_on_outside_click = true
        assert o.close_on_outside_click?
      end
    end

    context "on_close" do
      it "fires when the overlay is closed" do
        closed = 0
        o = Component::Overlay.new
        o.on_close = -> { closed += 1 }
        o.open
        o.close
        assert_equal 1, closed
      end

      # The whole reason it hangs off on_detached rather than #close: a driver
      # keeping its own record of open overlays must not be able to drift.
      it "fires when the overlay is removed straight off the screen" do
        closed = 0
        o = Component::Overlay.new
        o.on_close = -> { closed += 1 }
        o.open
        Screen.instance.remove_popup(o)
        assert_equal 1, closed
      end

      it "fires when the screen is torn down under it" do
        closed = 0
        o = Component::Overlay.new
        o.on_close = -> { closed += 1 }
        o.open
        Screen.close
        assert_equal 1, closed
        Screen.fake # the `after` hook closes again
      end

      it "does not fire when a closed overlay is closed again" do
        closed = 0
        o = Component::Overlay.new
        o.on_close = -> { closed += 1 }
        o.open
        o.close
        o.close
        assert_equal 1, closed
      end

      it "sees a closed overlay" do
        seen = nil
        o = Component::Overlay.new
        o.on_close = -> { seen = o.open? }
        o.open
        o.close
        assert_equal false, seen
      end
    end
  end
end
