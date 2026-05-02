# frozen_string_literal: true

module Tuile
  describe ScreenPane do
    before { Screen.fake }
    after { Screen.close }
    let(:pane) { Screen.instance.pane }

    it "is the root of the component tree" do
      assert_nil pane.parent
      assert_equal pane, pane.root
    end

    it "reports itself as attached to the screen" do
      assert pane.attached?
    end

    it "owns the status bar and parents it" do
      assert_instance_of Component::Label, pane.status_bar
      assert_equal pane, pane.status_bar.parent
    end

    it "is exposed via Screen#pane" do
      assert_equal pane, Screen.instance.pane
    end

    context "rect propagation" do
      it "lays out content and status bar when its rect is set" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        pane.rect = Rect.new(0, 0, 80, 24)
        assert_equal Rect.new(0, 0, 80, 23), layout.rect
        assert_equal Rect.new(0, 23, 80, 1), pane.status_bar.rect
      end

      it "relayouts on a height-only change" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        pane.rect = Rect.new(0, 0, 80, 24)
        pane.rect = Rect.new(0, 0, 80, 30)
        assert_equal Rect.new(0, 0, 80, 29), layout.rect
        assert_equal Rect.new(0, 29, 80, 1), pane.status_bar.rect
      end
    end

    context "parenting" do
      it "parents content when assigned" do
        layout = Component::Layout::Absolute.new
        Screen.instance.content = layout
        assert_equal pane, layout.parent
      end

      it "parents popups when added" do
        list = Component::List.new
        list.content = ["a"]
        popup = Component::Popup.new(content: list)
        Screen.instance.add_popup(popup)
        assert_equal pane, popup.parent
      end

      it "detaches popup parent when removed" do
        list = Component::List.new
        list.content = ["a"]
        popup = Component::Popup.new(content: list)
        Screen.instance.add_popup(popup)
        Screen.instance.remove_popup(popup)
        assert_nil popup.parent
      end
    end
  end
end
