# frozen_string_literal: true

module Tuile
  describe Component::InfoDialog do
    before { Screen.fake }
    after { Screen.close }

    it "is a Dialog" do
      assert Component::InfoDialog.new.is_a?(Component::Dialog)
    end

    it "has no body by default" do
      w = Component::InfoDialog.new("Help")
      assert_nil w.content
      assert_nil w.message
    end

    describe "constructor body dispatch" do
      it "routes an Array through lines=" do
        w = Component::InfoDialog.new("Help", %w[a b])
        assert w.content.is_a?(Component::List)
        assert_equal %w[a b], w.content.items.map(&:to_s)
      end

      it "routes a String through message=" do
        w = Component::InfoDialog.new("Help", "prose")
        assert w.content.is_a?(Component::TextView)
        assert_equal "prose", w.message
      end
    end

    describe "#message=" do
      it "renders a String in a TextView and reads the String back" do
        w = Component::InfoDialog.new("Help")
        w.message = "a long explanation"
        assert w.content.is_a?(Component::TextView)
        assert_equal "a long explanation", w.message
      end

      it "renders a StyledString in a TextView and reads it back" do
        w = Component::InfoDialog.new("Help")
        styled = StyledString.plain("styled prose")
        w.message = styled
        assert w.content.is_a?(Component::TextView)
        assert_equal styled, w.message
      end

      it "mounts a Component as-is" do
        w = Component::InfoDialog.new("Help")
        label = Component::Label.new("custom")
        w.message = label
        assert_same label, w.content
        assert_same label, w.message
      end

      it "clears the body on nil" do
        w = Component::InfoDialog.new("Help", "prose")
        w.message = nil
        assert_nil w.content
        assert_nil w.message
      end

      it "rejects other types" do
        w = Component::InfoDialog.new("Help")
        assert_raises(TypeError) { w.message = 42 }
      end

      it "wraps long prose instead of truncating it" do
        w = Component::InfoDialog.new("Help", "aaaa bbbb cccc", declared_size: Size.new(9, 6)).open
        Screen.instance.repaint
        rows = Screen.instance.buffer.region_text(w.absolute_rect)
        # A truncating List would show "aaaa bb" on one row; the wrap puts
        # each word on its own row.
        assert(rows.none? { _1.include?("aaaa bbbb") })
        assert(rows.any? { _1.include?("bbbb") })
      end
    end

    describe "#lines=" do
      it "populates a List, one item per row" do
        w = Component::InfoDialog.new("Help")
        w.lines = %w[foo bar]
        assert w.content.is_a?(Component::List)
        assert_equal %w[foo bar], w.content.items.map(&:to_s)
      end

      it "reads the mounted List back through message" do
        w = Component::InfoDialog.new("Help")
        w.lines = %w[foo bar]
        assert_same w.content, w.message
      end

      it "rejects a non-Array" do
        w = Component::InfoDialog.new("Help")
        assert_raises(TypeError) { w.lines = "not an array" }
      end
    end

    it "swaps presentations — the last writer wins" do
      w = Component::InfoDialog.new("Help", %w[a b])
      w.message = "prose"
      assert w.content.is_a?(Component::TextView)
      w.lines = %w[c d]
      assert w.content.is_a?(Component::List)
      assert_equal %w[c d], w.content.items.map(&:to_s)
    end

    describe "#open" do
      it "reopens after closing" do
        dialog = Component::InfoDialog.new("Help", ["hello"])
        dialog.open.close
        assert dialog.open.open?
      end

      it "puts the body inside the border" do
        dialog = Component::InfoDialog.new("Help", %w[foo bar baz]).open
        Screen.instance.repaint
        rows = Screen.instance.buffer.region_text(dialog.absolute_rect)
        assert rows[0].start_with?("┌Help")
        assert rows[1].start_with?("│ foo")
      end

      it "sizes the dialog to the half-screen default (content wraps within it)" do
        dialog = Component::InfoDialog.new("Help", ["hello"]).open
        # Dialogs are sized top-down, not to content: HALF of 160x50 = 80x25.
        assert_equal Size.new(80, 25), dialog.rect.size
      end

      it "accepts an explicit size" do
        dialog = Component::InfoDialog.new("Help", ["hello"], declared_size: Fraction::FULL).open
        assert_equal Size.new(160, 50), dialog.rect.size
      end

      it "accepts an empty list" do
        dialog = Component::InfoDialog.new("Help", []).open
        assert_equal [], dialog.content.items
      end

      it "closes on ESC like any dialog" do
        dialog = Component::InfoDialog.new("Help", ["hello"]).open
        dialog.handle_key? Keys::ESC
        assert !dialog.open?
      end
    end
  end
end
