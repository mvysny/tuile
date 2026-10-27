# frozen_string_literal: true

module Tuile
  describe Component::Panel do
    before { Screen.fake }
    after { Screen.close }

    describe "inherited bg_color" do
      it "tints the border cells with bg_color" do
        w = Component::Panel.new("Hi")
        Testing.place(w, Rect.new(0, 0, 6, 3))
        w.bg_color = 52
        painted = Testing.paint(w)
        assert_equal "┌", painted.cell(0, 0).grapheme
        assert_equal Color.new(52), painted.cell(0, 0).style.bg
      end
    end

    context "caption" do
      it "sets caption via constructor" do
        assert_equal StyledString::EMPTY, Component::Panel.new.caption
        assert_equal StyledString.plain("foo"), Component::Panel.new("foo").caption
      end

      it "sets caption via setter" do
        w = Component::Panel.new
        w.caption = "bar"
        assert_equal StyledString.plain("bar"), w.caption
      end

      it "accepts a StyledString as-is, and nil clears it" do
        styled = StyledString.styled("bar", fg: Color::RED)
        w = Component::Panel.new(styled)
        assert_equal styled, w.caption
        w.caption = nil
        assert_equal StyledString::EMPTY, w.caption
      end

      it "invalidates on caption change" do
        w = Component::Panel.new
        Screen.instance.content = w
        Screen.instance.invalidated_clear
        w.caption = "new"
        assert Screen.instance.invalidated?(w)
      end

      it "is a no-op when the caption is unchanged" do
        w = Component::Panel.new("same")
        Screen.instance.content = w
        Screen.instance.invalidated_clear
        w.caption = "same"
        assert !Screen.instance.invalidated?(w)
      end
    end

    context "border" do
      it "paints an all-dashes top border when the caption was never set" do
        w = Component::Panel.new
        Testing.place(w, Rect.new(0, 0, 6, 3))
        assert_equal "┌────┐", Testing.paint(w).region_text(Rect.new(0, 0, 6, 1)).join
      end

      it "keeps a double-width caption inside the box — clipping is by display width" do
        w = Component::Panel.new("日本語テキスト")
        Testing.place(w, Rect.new(0, 0, 10, 3))
        painted = Testing.paint(w)
        # inner width is 8: "日本語テ" fits exactly, then the closing corner.
        assert_equal "┌日本語テ┐", painted.region_text(Rect.new(0, 0, 10, 1)).join
      end

      it "fills the dash remainder by display width when a wide glyph is dropped" do
        w = Component::Panel.new("日本語")
        Testing.place(w, Rect.new(0, 0, 7, 3))
        painted = Testing.paint(w)
        # inner width is 5: "日本" (4 cols) fits, the third glyph is dropped,
        # and one dash fills the leftover column.
        assert_equal "┌日本─┐", painted.region_text(Rect.new(0, 0, 7, 1)).join
      end

      it "keeps the caption's own colors while inactive" do
        w = Component::Panel.new(StyledString.styled("Hi", fg: Color::RED))
        Testing.place(w, Rect.new(0, 0, 6, 3))
        assert_equal Color::RED, Testing.paint(w).cell(1, 0).style.fg
      end

      it "overrides the caption's colors with the border color while active" do
        w = Component::Panel.new(StyledString.styled("Hi", fg: Color::RED))
        Testing.place(w, Rect.new(0, 0, 6, 3))
        w.active = true
        assert_equal Screen.instance.theme.active_border_color, Testing.paint(w).cell(1, 0).style.fg
      end

      it "does not paint past rect.width on a degenerate 1-column window" do
        w = Component::Panel.new("Hi")
        Testing.place(w, Rect.new(0, 0, 1, 2))
        repaint(w)
        assert_equal "┌", Screen.instance.buffer.cell(0, 0).grapheme
        assert_equal " ", Screen.instance.buffer.cell(1, 0).grapheme
      end
    end

    context "active" do
      it "is not active by default" do
        assert !Component::Panel.new.active?
      end
    end

    context "focusable?" do
      it "returns true" do
        assert Component::Panel.new.focusable?
      end
    end

    context "children" do
      it "is empty when content is unset" do
        assert_equal [], Component::Panel.new.children
      end

      it "holds just the content component" do
        w = Component::Panel.new
        list = Component::List.new
        w.content = list
        assert_equal [list], w.children
      end
    end

    context "content" do
      it "is nil by default" do
        assert_nil Component::Panel.new.content
      end

      it "content= sets the content as a child of the window" do
        w = Component::Panel.new
        list = Component::List.new
        w.content = list
        assert_equal list, w.content
        assert_equal w, list.parent
      end

      it "content= refocuses to the window when the replaced content held focus" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        w = Component::Panel.new
        old = Component::List.new
        old.define_singleton_method(:focusable?) { true }
        w.content = old
        layout.add(w)
        screen.focused = old

        replacement = Component::List.new
        replacement.define_singleton_method(:focusable?) { true }
        w.content = replacement

        # Component::Panel's handle_focus cascade lands focus on the new content.
        assert_equal replacement, screen.focused
      end

      it "content= clears focus to the window when content is set to nil and held focus" do
        screen = Screen.instance
        layout = Component::Layout::Absolute.new
        screen.content = layout
        w = Component::Panel.new
        old = Component::List.new
        old.define_singleton_method(:focusable?) { true }
        w.content = old
        layout.add(w)
        screen.focused = old

        w.content = nil
        assert_equal w, screen.focused
      end
    end

    context "layout" do
      it "positions content inside the border (1px inset on all sides, 1px right border by default)" do
        w = Component::Panel.new
        w.content = Component::List.new
        Testing.place(w, Rect.new(5, 3, 20, 10))
        # border_right=1 → content width = 20-1-1=18, height = 10-2=8, one
        # border column and row in from the window's own top-left
        w.content.flush_layout
        assert_equal Rect.new(1, 1, 18, 8), w.content.rect
        assert_equal Rect.new(6, 4, 18, 8), w.content.absolute_rect
      end
    end

    context "scrollbar=" do
      let(:w) do
        w = Component::Panel.new
        w.content = Component::List.new
        Testing.place(w, Rect.new(0, 0, 20, 10))
        w
      end

      it "enabling scrollbar expands content width by 1 (drops right border margin)" do
        w.scrollbar = true
        # border_right=0 → width = 20-1-0=19
        w.content.flush_layout
        assert_equal 19, w.content.rect.width
      end

      it "disabling scrollbar restores content width" do
        w.scrollbar = true
        w.scrollbar = false
        w.content.flush_layout
        assert_equal 18, w.content.rect.width
      end

      it "enabling scrollbar sets content scrollbar_visibility to :visible" do
        w.scrollbar = true
        assert_equal :visible, w.content.scrollbar_visibility
      end

      it "disabling scrollbar sets content scrollbar_visibility to :gone" do
        w.scrollbar = true
        w.scrollbar = false
        assert_equal :gone, w.content.scrollbar_visibility
      end

      it "works with any content that responds to scrollbar_visibility= (e.g. TextView)" do
        w2 = Component::Panel.new
        w2.content = Component::TextView.new
        Testing.place(w2, Rect.new(0, 0, 20, 10))
        w2.scrollbar = true
        assert_equal :visible, w2.content.scrollbar_visibility
        w2.content.flush_layout
        assert_equal 19, w2.content.rect.width
      end

      it "raises Tuile::Error when content does not support scrollbar_visibility=" do
        w2 = Component::Panel.new
        w2.content = Component::Label.new
        Testing.place(w2, Rect.new(0, 0, 20, 10))
        err = assert_raises(Tuile::Error) { w2.scrollbar = true }
        assert_includes err.message, "scrollbar_visibility="
      end
    end

    # Panel no longer overrides #handle_key? — key delivery to content
    # is the dispatcher's job (Screen/ScreenPane capture + bubble), covered in
    # screen_pane_spec.

    context "mouse routing" do
      let(:w) do
        w = Component::Panel.new
        w.content = Component::List.new
        mount_at(w, Rect.new(0, 0, 20, 10))
        # content.rect = Rect.new(1, 1, 18, 8)
        w
      end

      it "ignores clicks on the border (outside content rect)" do
        called = false
        w.content.define_singleton_method(:handle_mouse_down?) { |_| called = true }
        # (0,0): outside content rect which starts at (1,1)
        Screen.instance.click(0, 0)
        assert !called
      end

      it "delegates clicks inside content rect" do
        called = false
        w.content.define_singleton_method(:handle_mouse_down?) { |_| called = true }
        # (2,2): inside content rect (1,1,18,8)
        Screen.instance.click(2, 2)
        assert called
      end
    end

    context "repaint" do
      it "smokes" do
        w = Component::Panel.new
        Testing.place(w, Rect.new(0, 0, 20, 20))
        painted = Testing.paint(w)
        assert_equal "┌", painted.cell(0, 0).grapheme
        assert_equal "┘", painted.cell(19, 19).grapheme
      end

      it "does not print when rect is empty" do
        w = Component::Panel.new # default rect (0,0,0,0) is empty
        repaint(w)
        assert Screen.instance.prints.empty?
      end

      it "draws the border in the theme's active_border color when active" do
        w = Component::Panel.new
        Testing.place(w, Rect.new(0, 0, 20, 10))
        w.active = true
        assert_equal Screen.instance.theme.active_border_color, Testing.paint(w).cell(0, 0).style.fg
      end

      it "leaves the border uncolored when inactive" do
        w = Component::Panel.new
        Testing.place(w, Rect.new(0, 0, 20, 10))
        assert_nil Testing.paint(w).cell(0, 0).style.fg
      end

      it "clears the interior itself when there is no content to cover it" do
        w = Component::Panel.new
        Testing.place(w, Rect.new(0, 0, 20, 10))
        Screen.instance.buffer.fill(Rect.new(0, 0, 20, 10), StyledString::Style::DEFAULT)
        (1..8).each { |y| (1..18).each { |x| Screen.instance.buffer.set_char(x, y, "X") } }
        repaint(w)
        assert_equal "│#{" " * 18}│", Screen.instance.buffer.row_text(1)[0, 20]
      end

      it "re-emits nothing when repainted unchanged, with a scrollbar and without" do
        # The border is painted over the cells the default repaint used to blank
        # first, so an unchanged frame costs nothing (`D_component_contract`).
        [false, true].each do |scrollbar|
          w = Component::Panel.new("Caption")
          list = Component::List.new
          list.lines = (1..40).map { "row #{_1}" }
          w.content = list
          w.scrollbar = scrollbar
          mount_at(w, Rect.new(0, 0, 40, 12))
          Screen.instance.repaint
          Screen.instance.clear
          Screen.instance.invalidate(w)
          Screen.instance.repaint
          # Only the frame's sync wrapper and cursor housekeeping, no cell writes.
          assert_equal "#{Ansi::SYNC_BEGIN}#{Ansi::SYNC_END}",
                       Screen.instance.prints.join.gsub(TTY::Cursor.hide, ""),
                       "scrollbar: #{scrollbar}"
        end
      end
    end
  end
end
