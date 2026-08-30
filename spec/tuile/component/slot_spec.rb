# frozen_string_literal: true

module Tuile
  describe Component::Slot do
    before { Screen.fake }
    after { Screen.close }

    let(:slot) { Component::Slot.new }

    context "content" do
      it "is empty by default" do
        assert_nil slot.content
      end

      it "accepts an occupant from the constructor" do
        label = Component::Label.new("hi")
        assert_equal label, Component::Slot.new(label).content
      end

      it "adopts the occupant" do
        label = Component::Label.new("hi")
        slot.content = label
        assert_equal slot, label.parent
        assert_equal [label], slot.children
      end

      it "sizes the occupant to its own rect" do
        slot.rect = Rect.new(3, 4, 10, 2)
        label = Component::Label.new("hi")
        slot.content = label
        assert_equal Rect.new(3, 4, 10, 2), label.rect
      end

      it "resizes the occupant when the slot moves" do
        slot.content = (label = Component::Label.new("hi"))
        slot.rect = Rect.new(1, 1, 8, 3)
        assert_equal Rect.new(1, 1, 8, 3), label.rect
      end

      it "detaches the previous occupant on swap" do
        old = Component::Label.new("old")
        slot.content = old
        slot.content = Component::Label.new("new")
        assert_nil old.parent
        assert_equal 1, slot.children.size
      end

      it "empties on nil" do
        slot.content = Component::Label.new("x")
        slot.content = nil
        assert_nil slot.content
        assert_equal [], slot.children
      end
    end

    context "an empty slot" do
      # The region is reserved, not collapsed: a dialog with no message shows
      # the hole rather than reflowing around it.
      it "clears the rect it was given" do
        Screen.instance.content = slot
        slot.rect = Rect.new(0, 0, 4, 1)
        Screen.instance.buffer.set_text(0, 0, StyledString.parse("XXXX"))
        slot.repaint
        assert_equal ["    "], Screen.instance.buffer.region_text(slot.rect)
      end

      it "paints nothing when its rect is empty" do
        Screen.instance.buffer.set_text(0, 0, StyledString.parse("XXXX"))
        slot.repaint
        assert_equal ["XXXX"], Screen.instance.buffer.region_text(Rect.new(0, 0, 4, 1))
      end
    end

    context "transparency" do
      it "is not a focus target" do
        refute slot.focusable?
        refute slot.tab_stop?
      end

      it "passes a click down to its occupant" do
        Screen.instance.content = slot
        slot.rect = Rect.new(0, 0, 10, 1)
        field = Component::TextField.new
        slot.content = field
        slot.handle_mouse(MouseEvent.new(:left, 2, 0))
        assert_equal field, Screen.instance.focused
      end

      it "hands a departing occupant's focus repair to the container" do
        # Repairing here would land focus on the slot itself, which has no
        # cursor and no keys.
        window = Component::Window.new
        content = Component::List.new
        window.content = content
        Screen.instance.content = window
        window.rect = Rect.new(0, 0, 20, 10)

        footer = Component::TextField.new
        window.footer = footer
        Screen.instance.focused = footer
        window.footer = nil

        assert_equal content, Screen.instance.focused
      end
    end
  end
end
