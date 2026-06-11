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
      assert_equal "a all", picker.content.lines.first.to_s
    end

    describe ".open" do
      it "opens as a popup wrapping a PickerWindow" do
        popup = Component::PickerWindow.open("foo", [%w[a all]]) {}
        assert popup.is_a?(Component::Popup)
        assert popup.content.is_a?(Component::PickerWindow)
        assert popup.open?
        popup.close
      end

      # Drive through the real dispatcher (Screen#handle_key): opening the
      # popup focuses the inner List, and keys reach the picker by capture +
      # bubble, exactly as in a running app.
      def press(key) = Screen.instance.send(:handle_key, key)

      it "doesn't call block when closed via q" do
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { raise "should not be called" }
        press("q")
        assert !popup.open?
      end

      it "selects first option on enter" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = _1 }
        press(Keys::ENTER)
        assert_equal "a", selected
        assert !popup.open?
      end

      it "selects correct option when its key is pressed" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = _1 }
        press("a")
        assert_equal "a", selected
        assert !popup.open?
      end

      it "does nothing if an unlisted key is pressed" do
        selected = nil
        popup = Component::PickerWindow.open("foo", [%w[a all]]) { selected = _1 }
        press("b")
        assert_nil selected
        assert popup.open?
      end
    end
  end
end
