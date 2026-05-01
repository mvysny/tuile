# frozen_string_literal: true

module Tuile
  describe PickerWindow do
    before { Screen.fake }
    after { Screen.close }
    let(:screen) { Screen.instance }

    it "smokes" do
      w = PickerWindow.new("foo", [%w[a all]]) {}
      screen.add_popup w
      w.close
    end

    it "opens as popup" do
      w = PickerWindow.open("foo", [%w[a all]]) {}
      assert w.open?
      w.close
    end

    it "doesnt call block if closed" do
      w = PickerWindow.new("foo", [%w[a all]]) { raise "should not be called" }
      screen.add_popup w
      w.handle_key("q")
      assert !w.open?
    end

    it "selects first option on enter" do
      selected = nil
      w = PickerWindow.new("foo", [%w[a all]]) { selected = it }
      screen.add_popup w
      w.handle_key(Keys::ENTER)
      assert_equal "a", selected
      assert !w.open?
    end

    it "selects correct option" do
      selected = nil
      w = PickerWindow.new("foo", [%w[a all]]) { selected = it }
      screen.add_popup w
      w.handle_key("a")
      assert_equal "a", selected
      assert !w.open?
    end

    it "does nothing if unlisted key is pressed" do
      selected = nil
      w = PickerWindow.new("foo", [%w[a all]]) { selected = it }
      screen.add_popup w
      w.handle_key("b")
      assert_nil selected
      assert w.open?
    end
  end
end
