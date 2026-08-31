# frozen_string_literal: true

module Tuile
  describe Component::InfoWindow do
    before { Screen.fake }
    after { Screen.close }

    it "is a Window" do
      assert Component::InfoWindow.new.is_a?(Component::Window)
    end

    it "has no body by default" do
      w = Component::InfoWindow.new("Help")
      assert_nil w.content
      assert_nil w.message
    end

    describe "constructor body dispatch" do
      it "routes an Array through lines=" do
        w = Component::InfoWindow.new("Help", %w[a b])
        assert w.content.is_a?(Component::List)
        assert_equal %w[a b], w.content.items.map(&:to_s)
      end

      it "routes a String through message=" do
        w = Component::InfoWindow.new("Help", "prose")
        assert w.content.is_a?(Component::TextView)
        assert_equal "prose", w.message
      end
    end

    describe "#message=" do
      it "renders a String in a TextView and reads the String back" do
        w = Component::InfoWindow.new("Help")
        w.message = "a long explanation"
        assert w.content.is_a?(Component::TextView)
        assert_equal "a long explanation", w.message
      end

      it "renders a StyledString in a TextView and reads it back" do
        w = Component::InfoWindow.new("Help")
        styled = StyledString.plain("styled prose")
        w.message = styled
        assert w.content.is_a?(Component::TextView)
        assert_equal styled, w.message
      end

      it "mounts a Component as-is" do
        w = Component::InfoWindow.new("Help")
        label = Component::Label.new("custom")
        w.message = label
        assert_same label, w.content
        assert_same label, w.message
      end

      it "clears the body on nil" do
        w = Component::InfoWindow.new("Help", "prose")
        w.message = nil
        assert_nil w.content
        assert_nil w.message
      end

      it "rejects other types" do
        w = Component::InfoWindow.new("Help")
        assert_raises(TypeError) { w.message = 42 }
      end

      it "wraps long prose instead of truncating it" do
        w = Component::InfoWindow.new("Help", "aaaa bbbb cccc")
        Screen.instance.content = w
        w.rect = Rect.new(0, 0, 9, 6)
        Screen.instance.repaint
        rows = Screen.instance.buffer.region_text(w.rect)
        # A truncating List would show "aaaa bb" on one row; the wrap puts
        # each word on its own row.
        assert(rows.none? { _1.include?("aaaa bbbb") })
        assert(rows.any? { _1.include?("bbbb") })
      end
    end

    describe "#lines=" do
      it "populates a List, one item per row" do
        w = Component::InfoWindow.new("Help")
        w.lines = %w[foo bar]
        assert w.content.is_a?(Component::List)
        assert_equal %w[foo bar], w.content.items.map(&:to_s)
      end

      it "reads the mounted List back through message" do
        w = Component::InfoWindow.new("Help")
        w.lines = %w[foo bar]
        assert_same w.content, w.message
      end

      it "rejects a non-Array" do
        w = Component::InfoWindow.new("Help")
        assert_raises(TypeError) { w.lines = "not an array" }
      end
    end

    it "swaps presentations — the last writer wins" do
      w = Component::InfoWindow.new("Help", %w[a b])
      w.message = "prose"
      assert w.content.is_a?(Component::TextView)
      w.lines = %w[c d]
      assert w.content.is_a?(Component::List)
      assert_equal %w[c d], w.content.items.map(&:to_s)
    end

    describe ".open" do
      it "adds a Popup to the popup stack" do
        Component::InfoWindow.open("Help", ["hello"])
        assert_equal 1, Screen.instance.pane.popups.size
        assert Screen.instance.pane.popups.first.is_a?(Component::Popup)
      end

      it "wraps an InfoWindow as the popup's content" do
        Component::InfoWindow.open("Help", ["hello"])
        wrapped = Screen.instance.pane.popups.first.content
        assert wrapped.is_a?(Component::InfoWindow)
        assert_equal "Help", wrapped.caption.to_s
      end

      it "populates the inner list with the given lines" do
        Component::InfoWindow.open("Help", %w[foo bar baz])
        list = Screen.instance.pane.popups.first.content.content
        assert_equal %w[foo bar baz], list.items.map(&:to_s)
      end

      it "renders a String body in a TextView" do
        Component::InfoWindow.open("Help", "wrapping prose")
        wrapped = Screen.instance.pane.popups.first.content
        assert wrapped.content.is_a?(Component::TextView)
        assert_equal "wrapping prose", wrapped.message
      end

      it "sizes the popup to the half-screen default (content wraps within it)" do
        Component::InfoWindow.open("Help", ["hello"])
        popup = Screen.instance.pane.popups.first
        # Popups are sized top-down, not to content: HALF of 160x50 = 80x25.
        assert_equal 80, popup.rect.width
        assert_equal 25, popup.rect.height
      end

      it "accepts an explicit size" do
        Component::InfoWindow.open("Help", ["hello"], declared_size: Fraction::FULL)
        popup = Screen.instance.pane.popups.first
        assert_equal 160, popup.rect.width
        assert_equal 50, popup.rect.height
      end

      it "accepts an empty list" do
        Component::InfoWindow.open("Help", [])
        wrapped = Screen.instance.pane.popups.first.content
        assert_equal [], wrapped.content.items
      end

      it "closes on ESC like any popup" do
        popup = Component::InfoWindow.open("Help", ["hello"])
        popup.handle_key Keys::ESC
        assert !popup.open?
      end
    end
  end
end
