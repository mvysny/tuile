# frozen_string_literal: true

module Tuile
  describe Component::InfoPopupWindow do
    before { Screen.fake }
    after { Screen.close }

    it "is a Window" do
      assert Component::InfoPopupWindow.new.is_a?(Component::Window)
    end

    it "preconfigures a List as its content" do
      w = Component::InfoPopupWindow.new("Help", %w[a b])
      assert w.content.is_a?(Component::List)
      assert_equal %w[a b], w.content.content
    end

    describe ".open" do
      it "adds a Popup to the popup stack" do
        Component::InfoPopupWindow.open("Help", ["hello"])
        assert_equal 1, Screen.instance.pane.popups.size
        assert Screen.instance.pane.popups.first.is_a?(Component::Popup)
      end

      it "wraps an InfoPopupWindow as the popup's content" do
        Component::InfoPopupWindow.open("Help", ["hello"])
        wrapped = Screen.instance.pane.popups.first.content
        assert wrapped.is_a?(Component::InfoPopupWindow)
        assert_equal "Help", wrapped.caption
      end

      it "populates the inner list with the given lines" do
        Component::InfoPopupWindow.open("Help", %w[foo bar baz])
        list = Screen.instance.pane.popups.first.content.content
        assert_equal %w[foo bar baz], list.content
      end

      it "auto-sizes the popup to the content" do
        Component::InfoPopupWindow.open("Help", ["hello"])
        popup = Screen.instance.pane.popups.first
        # Window content_size = inner_w+2, inner_h+2; List "hello" → inner_w=7, inner_h=1
        assert_equal 9, popup.rect.width
        assert_equal 3, popup.rect.height
      end

      it "accepts an empty list" do
        Component::InfoPopupWindow.open("Help", [])
        wrapped = Screen.instance.pane.popups.first.content
        assert_equal [], wrapped.content.content
      end

      it "closes on ESC like any popup" do
        popup = Component::InfoPopupWindow.open("Help", ["hello"])
        popup.handle_key Keys::ESC
        assert !popup.open?
      end
    end
  end
end
