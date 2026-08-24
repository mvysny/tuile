# frozen_string_literal: true

module Tuile
  describe Component::MenuBar do
    before { Screen.fake }
    after { Screen.close }

    # A bar of three menus, painting " File  Edit  View " — 18 columns, so a
    # 40-wide rect leaves a 22-column dead tail:
    #
    #   column  0     6     12    17
    #           ␣File␣␣Edit␣␣View␣
    def menu_bar(width: 40, focused: true)
      b = Component::MenuBar.new
      Screen.instance.content = b
      file = b.add_item("File")
      %w[New Open].each { |caption| file.add_item(caption) }
      b.add_item("Edit").add_item("Copy")
      b.add_item("View").add_item("Zoom")
      b.rect = Rect.new(0, 0, width, 1)
      b.focus if focused
      b
    end

    # Screen#handle_key is the (private) key-dispatch entry the event loop
    # drives; poke it directly to simulate typing without a real loop.
    def key(code) = Screen.instance.send(:handle_key, code)
    def popups = Screen.instance.pane.popups

    def strip(bar)
      bar.repaint
      Screen.instance.buffer.region_text(bar.rect).first
    end

    # The open panel's painted rows, rstripped.
    def panel_rows
      list = popups.last.instance_variable_get(:@list)
      list.repaint
      Screen.instance.buffer.region_text(list.rect).map(&:rstrip)
    end

    it "is a focusable, childless tab stop" do
      bar = menu_bar
      assert bar.focusable?
      assert bar.tab_stop?
      assert_empty bar.children
    end

    it "starts empty" do
      bar = Component::MenuBar.new
      assert_empty bar.items
      assert_equal 0, bar.highlighted_index
      assert_equal "", bar.keyboard_hint
    end

    describe "building the tree" do
      it "add_item appends a top-level item and hands back its handle" do
        bar = Component::MenuBar.new
        file = bar.add_item("File")
        assert_equal [file], bar.items
        assert_equal "File", file.caption.to_s
        refute file.submenu?
      end

      it "nests through the same method, without a depth limit" do
        deep = Component::MenuBar.new.add_item("a").add_item("b").add_item("c").add_item("d")
        assert_equal "d", deep.caption.to_s
      end

      it "an item with children is a submenu" do
        file = Component::MenuBar.new.add_item("File")
        file.add_item("New")
        assert file.submenu?
      end

      it "takes the listener as a block or a setter, and never constructs items directly" do
        log = []
        bar = Component::MenuBar.new
        bar.add_item("Save") { log << :block }
        bar.add_item("Quit").on_click = -> { log << :setter }
        bar.items.each { _1.on_click.call }
        assert_equal %i[block setter], log
        assert_raises(NoMethodError) { Component::MenuBar::Item.new(StyledString::EMPTY, nil) }
      end
    end

    describe "painting" do
      it "paints one padded segment per item, with no separator between them" do
        assert_equal " File  Edit  View", strip(menu_bar).rstrip
      end

      it "highlights the item Enter would open, but only while focused" do
        bar = menu_bar
        strip(bar)
        assert_equal Theme::DARK.active_bg_color, Screen.instance.buffer.cell(1, 0).style.bg
        Screen.instance.focused = nil
        strip(bar)
        assert_nil Screen.instance.buffer.cell(1, 0).style.bg
      end

      it "moves the highlight with the selection" do
        bar = menu_bar
        key(Keys::RIGHT_ARROW)
        strip(bar)
        assert_nil Screen.instance.buffer.cell(1, 0).style.bg
        assert_equal Theme::DARK.active_bg_color, Screen.instance.buffer.cell(7, 0).style.bg
      end

      it "clips an overflowing strip at the rect edge" do
        assert_equal " File  Ed", strip(menu_bar(width: 9))
      end
    end

    describe "extent" do
      it "covers the painted segments only" do
        assert_equal Rect.new(0, 0, 18, 1), menu_bar.extent
      end

      it "is clipped by a narrow rect, and empty before layout" do
        assert_equal Rect.new(0, 0, 9, 1), menu_bar(width: 9).extent
        assert_equal Rect.new(0, 0, 0, 1), Component::MenuBar.new.extent
      end
    end

    describe "keys, with no menu open" do
      it "LEFT / RIGHT move the highlight, clamping at both ends" do
        bar = menu_bar
        assert key(Keys::RIGHT_ARROW)
        assert_equal 1, bar.highlighted_index
        key(Keys::RIGHT_ARROW)
        key(Keys::RIGHT_ARROW)
        assert_equal 2, bar.highlighted_index
        3.times { key(Keys::LEFT_ARROW) }
        assert_equal 0, bar.highlighted_index
      end

      it "Enter, Space and Down each open the highlighted menu" do
        [Keys::ENTER, " ", Keys::DOWN_ARROW].each do |code|
          bar = menu_bar
          assert key(code)
          assert_equal 1, popups.size
          assert_equal [" New", " Open"], panel_rows
          bar.active = false
        end
      end

      it "lets every other key bubble, so an app's own keys keep working" do
        menu_bar
        refute key("s")
        refute key(Keys::UP_ARROW)
        refute key(Keys::ESC)
        assert_empty popups
      end

      it "fires a childless top-level item instead of opening a menu" do
        log = []
        bar = Component::MenuBar.new
        Screen.instance.content = bar
        bar.add_item("Quit") { log << :quit }
        bar.rect = Rect.new(0, 0, 40, 1)
        bar.focus
        assert key(Keys::ENTER)
        assert_equal [:quit], log
        assert_empty popups
      end

      it "handles nothing at all while empty" do
        bar = Component::MenuBar.new
        Screen.instance.content = bar
        bar.focus
        refute key(Keys::RIGHT_ARROW)
        refute key(Keys::ENTER)
      end
    end

    describe "keys, with a menu open" do
      it "forwards movement and closes on ESC" do
        menu_bar
        key(Keys::ENTER)
        assert key(Keys::DOWN_ARROW)
        assert key(Keys::ESC)
        assert_empty popups
      end

      # Quasi-modal, unlike the closed strip: an app key firing behind a visible
      # menu would be worse than a dead keystroke.
      it "swallows keys the cascade doesn't recognize" do
        menu_bar
        key(Keys::ENTER)
        assert key("s")
        assert_equal 1, popups.size
      end

      it "RIGHT on a leaf row steps to the next menu and opens it" do
        bar = menu_bar
        key(Keys::ENTER)
        assert key(Keys::RIGHT_ARROW) # "New" has no submenu
        assert_equal 1, bar.highlighted_index
        assert_equal [" Copy"], panel_rows
      end

      it "LEFT at the first level steps to the previous menu" do
        bar = menu_bar
        key(Keys::RIGHT_ARROW)
        key(Keys::ENTER)
        assert key(Keys::LEFT_ARROW)
        assert_equal 0, bar.highlighted_index
        assert_equal [" New", " Open"], panel_rows
      end

      # Reopening the same menu would throw away the submenu the user is
      # standing in, so an end-of-strip step leaves the cascade alone.
      it "steps to nothing at the ends, keeping the menu open" do
        bar = menu_bar
        key(Keys::ENTER)
        assert key(Keys::LEFT_ARROW)
        assert_equal 0, bar.highlighted_index
        assert_equal 1, popups.size
        assert_equal [" New", " Open"], panel_rows
      end
    end

    describe "the mouse" do
      it "opens the menu under the pointer, wherever in its segment" do
        bar = menu_bar
        bar.handle_mouse(MouseEvent.new(:left, 6, 0)) # "Edit"'s leading padding
        assert_equal 1, bar.highlighted_index
        assert_equal [" Copy"], panel_rows
      end

      it "closes the menu when its own segment is clicked again" do
        bar = menu_bar
        bar.handle_mouse(MouseEvent.new(:left, 1, 0))
        bar.handle_mouse(MouseEvent.new(:left, 1, 0))
        assert_empty popups
      end

      it "focuses but opens nothing from the blank tail" do
        bar = menu_bar(focused: false)
        bar.handle_mouse(MouseEvent.new(:left, 30, 0))
        assert_same bar, Screen.instance.focused
        assert_empty popups
      end
    end

    describe "closing on its own" do
      it "a changed rect closes the cascade — every panel position is derived" do
        bar = menu_bar
        key(Keys::ENTER)
        bar.rect = Rect.new(0, 0, 30, 1)
        assert_empty popups
      end

      it "an unchanged rect does not, so a relayout can't dismiss a menu" do
        bar = menu_bar
        key(Keys::ENTER)
        bar.rect = Rect.new(0, 0, 40, 1) # equal, but a different object
        assert_equal 1, popups.size
      end

      it "detaching closes it, so the panels can't outlive the bar" do
        menu_bar
        key(Keys::ENTER)
        Screen.instance.content = Component::Label.new
        assert_empty popups
      end

      it "leaving the focus chain closes it" do
        bar = menu_bar
        key(Keys::ENTER)
        Screen.instance.focused = nil
        assert_empty popups
        refute_nil bar.parent # sanity: closing the menu didn't detach the bar
      end
    end

    it "reports a hint that follows the open menu" do
      bar = menu_bar
      assert_includes bar.keyboard_hint, "←→"
      key(Keys::ENTER)
      assert_includes bar.keyboard_hint, "↑↓"
    end
  end
end
