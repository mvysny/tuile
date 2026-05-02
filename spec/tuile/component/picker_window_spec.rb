# frozen_string_literal: true

module Tuile
  describe Component::PickerWindow do
    before { Screen.fake }
    after { Screen.close }

    it "is a Window" do
      picker = Component::PickerWindow.new("foo", [%w[a all]]) {}
      assert picker.is_a?(Component::Window)
    end

    it "renders option lines into its inner list" do
      picker = Component::PickerWindow.new("foo", [%w[a all]]) {}
      assert picker.content.is_a?(Component::List)
      assert_equal "a all", Rainbow.uncolor(picker.content.lines.first)
    end

    describe ".open" do
      it "opens as a popup wrapping a PickerWindow" do
        popup = Component::PickerWindow.open("foo", [%w[a all]]) {}
        assert popup.is_a?(Component::Popup)
        assert popup.content.is_a?(Component::PickerWindow)
        assert popup.open?
        popup.close
      end

      it "doesn't call block when closed via q" do
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { raise "should not be called" }
        popup.handle_key("q")
        assert !popup.open?
      end

      it "selects first option on enter" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = it }
        popup.handle_key(Keys::ENTER)
        assert_equal "a", selected
        assert !popup.open?
      end

      it "selects correct option when its key is pressed" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = it }
        popup.handle_key("a")
        assert_equal "a", selected
        assert !popup.open?
      end

      it "does nothing if an unlisted key is pressed" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = it }
        popup.handle_key("b")
        assert_nil selected
        assert popup.open?
      end
    end
  end
end
