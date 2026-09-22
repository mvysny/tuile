# frozen_string_literal: true

module Tuile
  describe Testing::Gestures do
    let(:column) { Component::Layout::Vertical.new }
    let(:save) { Component::Button.new("Save").tap { _1.id = :save } }
    let(:field) { Component::TextField.new }

    let(:window) do
      Component::Window.new("Settings").tap do |w|
        w.content = column
        column.add(save)
        column.add(field)
        Screen.instance.content = w
        place(w, Rect.new(0, 0, 40, 10))
      end
    end

    describe "in a file that activates it" do
      using Testing::Gestures

      before { Screen.fake }
      after { Screen.close }

      it "clicks through the receiver" do
        clicked = false
        window
        save.on_click << -> { clicked = true }
        Testing.get(Component::Button, id: :save)._click
        assert clicked
      end

      it "assigns through the receiver, keeping assignment syntax" do
        window
        Testing.get(Component::TextField)._value = "Zaphod"
        assert_equal "Zaphod", field.value
      end

      it "delegates, so the gate is the module function's" do
        window
        save.visible = false
        assert_raises(Testing::AssertionError) { save._click }
      end

      it "is refused on a component that is not a field" do
        window
        e = assert_raises(Testing::AssertionError) { save._value = "Zaphod" }
        assert_includes e.message, "is not a field"
      end
    end

    # The refinement is lexically scoped: activating it above does not reach
    # this block, which is what lets one file mix refined and unrefined
    # examples — and what keeps `lib/` and an app free of it.
    describe "in a scope that does not" do
      before { Screen.fake }
      after { Screen.close }

      it "adds nothing to Component" do
        window
        refute save.respond_to?(:_click)
        assert_raises(NoMethodError) { save._click }
      end
    end
  end
end
