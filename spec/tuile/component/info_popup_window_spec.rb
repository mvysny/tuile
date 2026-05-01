# frozen_string_literal: true

module Tuile
  describe Component::InfoPopupWindow do
    before { Screen.fake }
    after { Screen.close }

    it "is a PopupWindow" do
      assert Component::InfoPopupWindow.new.is_a?(Component::PopupWindow)
    end

    describe ".open" do
      it "adds an InfoPopupWindow to the popup stack" do
        Component::InfoPopupWindow.open("Help", ["hello"])
        assert_equal 1, Screen.instance.pane.popups.size
        assert Screen.instance.pane.popups.first.is_a?(Component::InfoPopupWindow)
      end

      it "sets the caption" do
        Component::InfoPopupWindow.open("Help", ["hello"])
        assert_equal "Help", Screen.instance.pane.popups.first.caption
      end

      it "populates the inner list with the given lines" do
        Component::InfoPopupWindow.open("Help", %w[foo bar baz])
        list = Screen.instance.pane.popups.first.content
        assert_equal %w[foo bar baz], list.content
      end

      it "auto-sizes the window to the content" do
        Component::InfoPopupWindow.open("Help", ["hello"])
        w = Screen.instance.pane.popups.first
        # 5-char line + 2 border + 2 padding = 9 wide; 1 line + 2 border = 3 tall
        assert_equal 9, w.rect.width
        assert_equal 3, w.rect.height
      end

      it "accepts an empty list" do
        Component::InfoPopupWindow.open("Help", [])
        assert_equal [], Screen.instance.pane.popups.first.content.content
      end

      it "closes on ESC like any popup" do
        Component::InfoPopupWindow.open("Help", ["hello"])
        w = Screen.instance.pane.popups.first
        w.handle_key Keys::ESC
        assert !w.open?
      end
    end
  end
end
