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

    # The same bar plus a top-level *button* — an item with a listener and no
    # menu — as the sampler's "About" is, painting
    # " File  Edit  View  About ".
    def menu_bar_with_button(log)
      bar = menu_bar
      bar.add_item("About") { log << :about }
      bar
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

      # Stepping *highlights*; it must not press. Otherwise walking the strip
      # fires every top-level button on it — and the old menu was left standing
      # over the action's own output.
      it "steps onto a top-level button without activating it, closing the menu" do
        log = []
        bar = menu_bar_with_button(log)
        key(Keys::RIGHT_ARROW)
        key(Keys::ENTER) # Edit's menu
        assert key(Keys::RIGHT_ARROW) # Edit's rows are all leaves, so this steps
        assert key(Keys::RIGHT_ARROW) # …onto "View", then onto "About"
        assert_equal 3, bar.highlighted_index
        assert_empty log, "arrowing past a button must not fire it"
        assert_empty popups, "the stepped-away-from menu must not be left open"
      end

      it "Enter then fires the button it stepped onto" do
        log = []
        menu_bar_with_button(log)
        3.times { key(Keys::RIGHT_ARROW) }
        assert key(Keys::ENTER)
        assert_equal [:about], log
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

      it "closes an open menu before firing a clicked top-level button" do
        log = []
        bar = menu_bar_with_button(log)
        bar.handle_mouse(MouseEvent.new(:left, 1, 0)) # open File
        assert_equal 1, popups.size
        bar.handle_mouse(MouseEvent.new(:left, 19, 0)) # "About"
        assert_equal [:about], log
        assert_empty popups
      end

      it "focuses but opens nothing from the blank tail" do
        bar = menu_bar(focused: false)
        bar.handle_mouse(MouseEvent.new(:left, 30, 0))
        assert_same bar, Screen.instance.focused
        assert_empty popups
      end

      # The pane dismisses every panel the click missed
      # ({Popup#close_on_outside_click?}); the cascade's own level stack is
      # reconciled from each panel's on_close, so the bar must not be left
      # believing a menu is still open. Driven through the *pane*, since that
      # is where dismissal lives.
      context "a click outside the cascade" do
        def click(x, y) = Screen.instance.pane.handle_mouse(MouseEvent.new(:left, x, y))

        # A two-level cascade: "Deep" holds "Sub" (which holds "Leaf") and a
        # sibling "Other" submenu to truncate back to.
        def nested_bar
          bar = menu_bar
          deep = bar.add_item("Deep")
          deep.add_item("Sub").add_item("Leaf").add_item("Twig")
          deep.add_item("Other").add_item("Thing")
          bar.rect = Rect.new(0, 0, 60, 1)
          bar.handle_mouse(MouseEvent.new(:left, 20, 0)) # open "Deep"
          key(Keys::RIGHT_ARROW) # drill into "Sub"
          assert_equal 2, popups.size
          bar
        end

        it "closes the whole cascade, however deep" do
          nested_bar
          click(50, 0) # the strip's dead tail
          assert_empty popups
        end

        # Panels sit *beside* each other, so a deeper one does not lie within
        # its parent's rect. Each panel therefore owns the one it dropped out
        # of; without that chain, drilling by mouse dismissed every shallower
        # panel — File would vanish the moment you clicked into its submenu.
        it "does not dismiss the shallower panels when a deeper one is clicked" do
          bar = nested_bar
          l0, l1 = popups
          click(l1.rect.left + 1, l1.rect.top) # "Leaf" -> drills a third level

          assert_equal 3, popups.size
          assert l0.open?, "the File panel must survive a click on its own submenu"
          assert l1.open?
          assert_equal 3, bar.instance_variable_get(:@cascade).depth
        end

        # Truncation is the driver's job, not the pane's: clicking a row moves
        # the cursor, and `on_cursor_changed` drops the levels below it.
        it "still truncates when a shallower panel's sibling is clicked" do
          bar = nested_bar
          l0 = popups.first
          click(l0.rect.left + 1, l0.rect.top + 1) # "Other", the sibling of "Sub"

          assert_equal 2, popups.size, "levels 1-2 replaced by Other's own panel"
          assert_equal 2, bar.instance_variable_get(:@cascade).depth
        end

        # The direct guard on the on_close wiring: popups going away is not
        # enough, the cascade's own level stack has to shrink with them.
        it "reconciles the cascade's level stack, not just the popups" do
          bar = nested_bar
          cascade = bar.instance_variable_get(:@cascade)

          click(50, 0)
          assert_equal 0, cascade.depth
          assert !cascade.open?
        end

        it "leaves the bar ready to open a menu again" do
          nested_bar
          click(50, 0)

          key(Keys::ENTER)
          assert_equal 1, popups.size, "a stale level stack would swallow this"
        end
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

    describe "mnemonics" do
      # The worked example that settled the design: File > Export and top-level
      # Edit both bind "e". They are never in the same lookup, so there is
      # nothing to arbitrate.
      def mnemonic_bar
        bar = Component::MenuBar.new
        Screen.instance.content = bar
        file = bar.add_item("File", mnemonic: "f")
        file.add_item("Export", mnemonic: "e") { @fired = :export }
        file.add_item("Quit", mnemonic: "q") { @fired = :quit }
        bar.add_item("Edit", mnemonic: "e").add_item("Copy", mnemonic: "c") { @fired = :copy }
        bar.rect = Rect.new(0, 0, 40, 1)
        bar.focus
        bar
      end

      describe "registration" do
        it "rejects a duplicate among siblings, not across levels" do
          bar = Component::MenuBar.new
          file = bar.add_item("File", mnemonic: "f")
          file.add_item("Export", mnemonic: "e")

          # Same letter one level up: legal, different sibling set.
          bar.add_item("Edit", mnemonic: "e")
          # Same letter as its own parent: legal too.
          file.add_item("Find", mnemonic: "f")

          err = assert_raises(ArgumentError) { bar.add_item("Explore", mnemonic: "E") }
          assert_includes err.message, "duplicate"
        end

        it "rejects a space, which Space already means" do
          bar = Component::MenuBar.new
          err = assert_raises(ArgumentError) { bar.add_item("File", mnemonic: " ") }
          assert_includes err.message, "space"
        end

        it "rejects a non-printable, a multi-character string and a wide glyph" do
          bar = Component::MenuBar.new
          ["\e", "ab", "漢", ""].each do |bad|
            assert_raises(ArgumentError, "expected #{bad.inspect} to be rejected") do
              bar.add_item("File", mnemonic: bad)
            end
          end
        end

        it "stores the mnemonic downcased and reports it in inspect" do
          item = Component::MenuBar.new.add_item("File", mnemonic: "F")
          assert_equal "f", item.mnemonic
          assert_includes item.inspect, "[f]"
        end

        it "leaves mnemonic nil when none is given" do
          assert_nil Component::MenuBar.new.add_item("File").mnemonic
        end
      end

      describe "the live set" do
        it "opens the top-level menu the letter names" do
          bar = mnemonic_bar
          assert key("f")
          assert_equal 0, bar.highlighted_index
          assert_equal [" Export", " Quit"], panel_rows
        end

        it "matches case-insensitively" do
          mnemonic_bar
          assert key("F")
          assert_equal 1, popups.size
        end

        # 'f' then 'q' — two keystrokes, each against a different live set.
        it "walks File > Quit as a sequence" do
          mnemonic_bar
          key("f")
          assert key("q")
          assert_equal :quit, @fired
          assert_empty popups
        end

        # The Export/Edit case: with File open, top-level Edit is not a
        # candidate, so 'e' fires Export.
        it "prefers the open level over a same-letter top-level item" do
          mnemonic_bar
          key("f")
          assert key("e")
          assert_equal :export, @fired
        end

        it "drills into a submenu and moves the live set with it" do
          bar = Component::MenuBar.new
          Screen.instance.content = bar
          file = bar.add_item("File", mnemonic: "f")
          file.add_item("Export", mnemonic: "e").add_item("PDF", mnemonic: "p") { @fired = :pdf }
          bar.rect = Rect.new(0, 0, 40, 1)
          bar.focus

          key("f")
          key("e")
          assert_equal 2, popups.size, "the submenu should be open beside its parent"
          assert key("p")
          assert_equal :pdf, @fired
        end

        it "fires a top-level button rather than opening an empty menu" do
          bar = mnemonic_bar
          bar.add_item("About", mnemonic: "a") { @fired = :about }
          assert key("a")
          assert_equal :about, @fired
          assert_empty popups
        end

        # No fallback: 'v' matches nothing in File's menu, and must not reach
        # the top-level set and tear the open menu down.
        it "swallows a miss instead of falling back to a shallower level" do
          bar = mnemonic_bar
          bar.add_item("View", mnemonic: "v")
          key("f")

          assert key("v")
          assert_equal [" Export", " Quit"], panel_rows, "File's menu should still be the open one"
          assert_equal 0, bar.highlighted_index
        end

        it "lets an unmatched printable bubble while the strip is closed" do
          mnemonic_bar
          refute key("z")
        end
      end

      describe "the bell" do
        def bel_count = Screen.instance.prints.join.count(Ansi::BEL)

        it "rings for a printable swallowed by an open menu" do
          mnemonic_bar
          key("f")
          Screen.instance.clear

          key("z")
          assert_equal 1, bel_count
        end

        it "stays silent for a swallowed non-printable" do
          mnemonic_bar
          key("f")
          Screen.instance.clear

          key(Keys::HOME)
          key("\e[?") # the junk Keys.getkey returns for an unknown sequence
          assert_equal 0, bel_count
        end

        it "stays silent while the strip is closed — the key is not a miss, it bubbles" do
          mnemonic_bar
          Screen.instance.clear

          key("z")
          assert_equal 0, bel_count
        end

        it "stays silent when a mnemonic matched" do
          mnemonic_bar
          key("f")
          Screen.instance.clear

          key("q")
          assert_equal 0, bel_count
        end
      end

      describe "the cue" do
        def underlined(styled) = styled.spans.select { |span| span.style.underline }.map(&:text)

        it "underlines the mnemonic in the caption" do
          item = Component::MenuBar.new.add_item("File", mnemonic: "f")
          assert_equal ["F"], underlined(item.cued_caption)
          assert_equal "File", item.cued_caption.to_s
        end

        it "prefers the exact-case occurrence" do
          upper = Component::MenuBar.new.add_item("Save As", mnemonic: "A")
          lower = Component::MenuBar.new.add_item("Save As", mnemonic: "a")

          assert_equal ["A"], underlined(upper.cued_caption)
          assert_equal ["a"], underlined(lower.cued_caption)
        end

        # A character index is not a column: the wide prefix has to be measured.
        it "places the underline by columns, not by character index" do
          item = Component::MenuBar.new.add_item("漢File", mnemonic: "f")
          assert_equal ["F"], underlined(item.cued_caption)
        end

        it "draws no cue when the character is absent from the caption" do
          item = Component::MenuBar.new.add_item("~/notes.txt", mnemonic: "1")
          assert_equal item.caption, item.cued_caption
          assert_empty underlined(item.cued_caption)
          assert_equal "1", item.mnemonic, "the mnemonic still fires without a cue"
        end

        it "draws the cue on the strip whether or not the bar has focus" do
          bar = Component::MenuBar.new
          Screen.instance.content = bar
          bar.add_item("File", mnemonic: "f")
          bar.rect = Rect.new(0, 0, 40, 1)
          bar.repaint

          assert_includes Screen.instance.buffer.region_ansi(bar.rect).first, "\e[4m"
        end

        # with_bg preserves other attributes, so the highlight can't eat the cue.
        it "survives the focused highlight" do
          bar = mnemonic_bar
          bar.repaint
          row = Screen.instance.buffer.region_ansi(bar.rect).first

          assert_includes row, "\e[4m"
        end

        it "underlines the mnemonic in an open menu's rows too" do
          mnemonic_bar
          key("f")
          list = popups.last.instance_variable_get(:@list)
          list.repaint

          assert_includes Screen.instance.buffer.region_ansi(list.rect).join, "\e[4m"
        end
      end

      # Paste rides its own path off the key ladder, so it can never fire one.
      it "is not driven by a paste" do
        mnemonic_bar
        Screen.instance.paste("fq")

        assert_empty popups
        assert_nil @fired
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
