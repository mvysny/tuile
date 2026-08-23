# frozen_string_literal: true

module Tuile
  describe Component::TabSheet do
    before { Screen.fake }
    after { Screen.close }

    # A pane counting the lifecycle hooks it sees as it is shown and hidden.
    def lifecycle_pane
      Class.new(Component) do
        attr_reader :attaches, :detaches

        def initialize
          super
          @attaches = 0
          @detaches = 0
        end

        def on_attached = @attaches += 1
        def on_detached = @detaches += 1
      end.new
    end

    # A sheet with `count` tabs, each holding a {Component::TextField} pane,
    # mounted on the screen and laid out 40x5.
    def sheet(count: 2)
      sheet = Component::TabSheet.new
      Screen.instance.content = sheet
      count.times { |i| sheet.add_tab("Tab#{i}", Component::TextField.new) }
      sheet.rect = Rect.new(0, 0, 40, 5)
      sheet
    end

    it "starts with the strip as its only child" do
      sheet = Component::TabSheet.new
      assert_equal [sheet.strip], sheet.children
      assert_nil sheet.pane
      assert_empty sheet.tabs
    end

    it "is neither focusable nor a tab stop — the strip and the pane carry focus" do
      sheet = Component::TabSheet.new
      refute sheet.focusable?
      refute sheet.tab_stop?
    end

    context "add_tab" do
      it "shows the first tab's pane immediately" do
        sheet = Component::TabSheet.new
        pane = Component::Label.new("First")
        tab = sheet.add_tab("First", pane)
        assert_equal pane, sheet.pane
        assert_equal tab, sheet.selected
      end

      it "leaves the shown pane alone for later tabs" do
        sheet = Component::TabSheet.new
        first = Component::Label.new("First")
        sheet.add_tab("First", first)
        sheet.add_tab("Second", Component::Label.new("Second"))
        assert_equal first, sheet.pane
      end

      it "keeps children as [strip, pane], in that order" do
        sheet = sheet(count: 3)
        assert_equal [sheet.strip, sheet.pane], sheet.children
        sheet.select_next
        assert_equal [sheet.strip, sheet.pane], sheet.children
      end

      it "maps each tab to its pane" do
        sheet = Component::TabSheet.new
        pane = Component::Label.new("First")
        tab = sheet.add_tab("First", pane)
        assert_equal pane, sheet.pane_for(tab)
      end

      it "rejects a non-Component pane" do
        assert_raises(TypeError) { Component::TabSheet.new.add_tab("Nope", "not a component") }
      end

      it "rejects a pane already used by another tab — a component has one parent" do
        sheet = Component::TabSheet.new
        pane = Component::Label.new("Shared")
        sheet.add_tab("First", pane)
        assert_raises(ArgumentError) { sheet.add_tab("Second", pane) }
      end
    end

    context "the swap" do
      it "detaches the outgoing pane and attaches the incoming one" do
        sheet = sheet(count: 2)
        first = sheet.pane
        sheet.select_next
        second = sheet.pane
        refute first.attached?
        assert_nil first.parent
        assert second.attached?
        assert_equal sheet, second.parent
      end

      it "fires on_detached on the outgoing pane and on_attached on the incoming one" do
        sheet = Component::TabSheet.new
        Screen.instance.content = sheet
        first = lifecycle_pane
        second = lifecycle_pane
        sheet.add_tab("First", first)
        sheet.add_tab("Second", second)
        assert_equal [1, 0], [first.attaches, first.detaches]
        sheet.select_next
        assert_equal [1, 1], [first.attaches, first.detaches]
        assert_equal [1, 0], [second.attaches, second.detaches]
        sheet.select_previous
        assert_equal [2, 1], [first.attaches, first.detaches]
      end

      it "lays the incoming pane out below the strip" do
        sheet = sheet(count: 2)
        sheet.select_next
        assert_equal Rect.new(0, 0, 40, 1), sheet.strip.rect
        assert_equal Rect.new(0, 1, 40, 4), sheet.pane.rect
      end

      it "keeps a hidden pane's state, so it comes back as the user left it" do
        sheet = Component::TabSheet.new
        Screen.instance.content = sheet
        field = Component::TextField.new
        sheet.add_tab("First", field)
        sheet.add_tab("Second", Component::Label.new("Second"))
        sheet.rect = Rect.new(0, 0, 40, 5)
        field.text = "typed"
        sheet.select_next
        sheet.select_previous
        assert_equal "typed", field.text
      end

      it "is a no-op when the selection is re-assigned to the selected tab" do
        sheet = sheet(count: 2)
        pane = sheet.pane
        sheet.selected = sheet.tabs.first
        assert_same pane, sheet.pane
        assert_equal [sheet.strip, pane], sheet.children
      end
    end

    context "focus" do
      it "lands on the strip when the sheet itself is focused" do
        sheet = sheet(count: 2)
        Screen.instance.focused = sheet
        assert_equal sheet.strip, Screen.instance.focused
      end

      it "falls back to the strip when the focused pane is swapped away" do
        sheet = sheet(count: 2)
        Screen.instance.focused = sheet.pane
        sheet.select_next
        assert_equal sheet.strip, Screen.instance.focused
      end

      it "leaves focus alone when it was outside the outgoing pane" do
        sheet = sheet(count: 2)
        Screen.instance.focused = sheet.strip
        sheet.select_next
        assert_equal sheet.strip, Screen.instance.focused
      end

      it "puts the strip before the pane in the Tab cycle" do
        sheet = sheet(count: 2)
        Screen.instance.focused = sheet.strip
        Screen.instance.focus_next
        assert_equal sheet.pane, Screen.instance.focused
      end

      it "keeps a hidden pane out of the Tab cycle entirely" do
        sheet = sheet(count: 2)
        hidden = sheet.pane_for(sheet.tabs.last)
        stops = []
        Screen.instance.pane.on_tree { |c| stops << c if c.tab_stop? }
        assert_includes stops, sheet.pane
        refute_includes stops, hidden
      end
    end

    context "remove_tab" do
      it "shows the tab that slid into place and forgets the removed pane" do
        sheet = sheet(count: 3)
        tab = sheet.tabs.first
        first = sheet.pane
        second = sheet.pane_for(sheet.tabs[1])
        assert_equal first, sheet.remove_tab(tab)
        assert_equal second, sheet.pane
        assert_nil sheet.pane_for(tab)
        refute first.attached?
      end

      it "leaves the shown pane alone when another tab is removed" do
        sheet = sheet(count: 3)
        shown = sheet.pane
        sheet.remove_tab(sheet.tabs.last)
        assert_same shown, sheet.pane
        assert_equal [sheet.strip, shown], sheet.children
      end

      it "leaves the strip alone as its only child once the last tab goes" do
        sheet = sheet(count: 1)
        pane = sheet.pane
        sheet.remove_tab(sheet.tabs.first)
        assert_nil sheet.pane
        assert_equal [sheet.strip], sheet.children
        refute pane.attached?
      end

      it "refuses a tab from another sheet" do
        foreign = Component::TabSheet.new.add_tab("Foreign", Component::Label.new("x"))
        assert_raises(ArgumentError) { sheet.remove_tab(foreign) }
      end
    end

    context "on_tab_selected" do
      it "fires after the pane has been swapped in" do
        sheet = sheet(count: 2)
        seen = nil
        sheet.on_tab_selected = ->(_index, _tab) { seen = sheet.pane }
        sheet.select_next
        assert_same sheet.pane, seen
      end

      it "reports the index and tab, and (nil, nil) once the last tab is gone" do
        sheet = sheet(count: 1)
        log = []
        sheet.on_tab_selected = ->(index, tab) { log << [index, tab&.caption&.to_s] }
        sheet.add_tab("Second", Component::Label.new("Second"))
        sheet.select_next
        sheet.remove_tab(sheet.tabs[1])
        sheet.remove_tab(sheet.tabs[0])
        assert_equal [[1, "Second"], [0, "Tab0"], [nil, nil]], log
      end
    end

    context "painting" do
      it "puts the strip on the top row and the pane below it" do
        sheet = Component::TabSheet.new
        Screen.instance.content = sheet
        sheet.add_tab("First", Component::Label.new("PANE ONE"))
        sheet.add_tab("Second", Component::Label.new("PANE TWO"))
        sheet.rect = Rect.new(0, 0, 20, 3)
        Screen.instance.repaint
        buffer = Screen.instance.buffer
        assert_equal " First │ Second     ", buffer.region_text(sheet.strip.rect).join
        assert_equal "PANE ONE            ", buffer.region_text(sheet.pane.rect).first
      end

      # The symptom that found the framework bug: focusing the strip invalidates
      # the focus chain, an ancestor layout with gaps clears its whole rect, and
      # the pane's cells are only repainted if the invalidation cascades through
      # the sheet — whose children tile it.
      it "keeps the pane painted when the strip takes focus" do
        gappy = Component::Layout::Vertical.new(spacing: 1)
        Screen.instance.content = gappy
        sheet = Component::TabSheet.new
        sheet.add_tab("First", Component::Label.new("PANE ONE"))
        gappy.add(Component::Label.new("prompt"), Component::Layout::Fixed[1])
        gappy.add(sheet, Component::Layout::Expand[1])
        gappy.rect = Rect.new(0, 0, 20, 6)
        Screen.instance.repaint

        Screen.instance.focused = sheet.strip
        Screen.instance.repaint
        assert_equal "PANE ONE            ", Screen.instance.buffer.region_text(sheet.pane.rect).first
      end

      it "repaints the new pane over the old one's cells" do
        sheet = Component::TabSheet.new
        Screen.instance.content = sheet
        sheet.add_tab("First", Component::Label.new("PANE ONE"))
        sheet.add_tab("Second", Component::Label.new("TWO"))
        sheet.rect = Rect.new(0, 0, 20, 3)
        Screen.instance.repaint
        sheet.select_next
        Screen.instance.repaint
        assert_equal "TWO                 ", Screen.instance.buffer.region_text(sheet.pane.rect).first
      end
    end

    context "delegators" do
      it "forwards the selection API to the strip" do
        sheet = sheet(count: 3)
        assert_equal sheet.strip.tabs, sheet.tabs
        sheet.selected_index = 2
        assert_equal 2, sheet.selected_index
        assert_equal sheet.strip.selected, sheet.selected
        sheet.selected = sheet.tabs.first
        assert_equal 0, sheet.strip.selected_index
        assert sheet.select_next
        assert_equal 1, sheet.selected_index
        assert sheet.select_previous
        assert_equal 0, sheet.selected_index
      end

      it "reports no strip to move on an empty sheet" do
        sheet = Component::TabSheet.new
        refute sheet.select_next
        refute sheet.select_previous
      end

      it "passes the separator through to the strip" do
        sheet = Component::TabSheet.new(separator: "|")
        assert_equal StyledString.plain("|"), sheet.strip.separator
      end
    end
  end
end
