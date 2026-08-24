# frozen_string_literal: true

module Tuile
  describe Component::Tabs do
    before { Screen.fake }
    after { Screen.close }

    # A strip of three tabs, painting " Details │ Payment │ Shipping" — 30
    # columns, so a 40-wide rect leaves a 10-column dead tail:
    #
    #   column  0         9        19        29
    #           ␣Details␣│␣Payment␣│␣Shipping␣
    def tabs(width: 40, active: false, captions: %w[Details Payment Shipping])
      strip = Component::Tabs.new
      captions.each { |caption| strip.add_tab(caption) }
      strip.rect = Rect.new(0, 0, width, 1)
      strip.active = active
      strip
    end

    # Attaches the strip to the screen, so invalidation and click-to-focus —
    # both gated on `attached?` — actually do something.
    def attached_tabs(**kwargs)
      layout = Component::Layout::Absolute.new
      Screen.instance.content = layout
      tabs(**kwargs).tap { layout.add(_1) }
    end

    # Records every `on_tab_selected` call as `[index, caption]`.
    def recorder(strip)
      [].tap { |log| strip.on_tab_selected = ->(index, tab) { log << [index, tab&.caption&.to_s] } }
    end

    it "starts empty, with no selection" do
      strip = Component::Tabs.new
      assert_empty strip.tabs
      assert_nil strip.selected
      assert_nil strip.selected_index
    end

    it "is focusable and a tab stop" do
      strip = Component::Tabs.new
      assert strip.focusable?
      assert strip.tab_stop?
    end

    context "tabs" do
      it "returns the tabs in strip order" do
        strip = Component::Tabs.new
        first = strip.add_tab("First")
        second = strip.add_tab("Second")
        assert_equal [first, second], strip.tabs
      end

      it "parses a String caption, and accepts a StyledString as-is" do
        strip = Component::Tabs.new
        assert_equal StyledString.plain("Plain"), strip.add_tab("Plain").caption
        styled = StyledString.styled("Red", fg: :red)
        assert_equal styled, strip.add_tab(styled).caption
      end

      it "accepts a nil caption" do
        assert Component::Tabs.new.add_tab.caption.empty?
      end

      it "selects the first tab added, and leaves the selection alone after that" do
        strip = Component::Tabs.new
        first = strip.add_tab("First")
        assert_equal first, strip.selected
        assert_equal 0, strip.selected_index
        strip.add_tab("Second")
        assert_equal first, strip.selected
      end
    end

    context "Tab" do
      it "cannot be constructed directly" do
        assert_raises(NoMethodError) { Component::Tabs::Tab.new }
      end

      it "reports whether it is selected" do
        strip = tabs
        assert strip.tabs.first.selected?
        refute strip.tabs.last.selected?
      end

      it "repaints the strip when its caption changes" do
        strip = attached_tabs
        Screen.instance.invalidated_clear
        strip.tabs.first.caption = "Renamed"
        assert Screen.instance.invalidated?(strip)
      end

      it "ignores a caption assignment that changes nothing" do
        strip = attached_tabs
        Screen.instance.invalidated_clear
        strip.tabs.first.caption = "Details"
        refute Screen.instance.invalidated?(strip)
      end

      it "removes itself through its own handle" do
        strip = tabs
        tab = strip.tabs.last
        tab.remove
        assert_equal(%w[Details Payment], strip.tabs.map { _1.caption.to_s })
        refute tab.attached?
      end

      it "is a silent no-op when removed twice" do
        tab = tabs.tabs.first
        tab.remove
        tab.remove
      end

      context "once removed" do
        let(:removed) { tabs.tabs.first.tap(&:remove) }

        it "keeps its caption readable, so an error message can still name it" do
          assert_equal "Details", removed.caption.to_s
          assert_includes removed.inspect, "removed"
        end

        it "raises on every mutator and on every reader that consults the strip" do
          assert_raises(RuntimeError) { removed.caption = "Nope" }
          assert_raises(RuntimeError) { removed.selected? }
        end
      end

      it "is refused by a strip that does not own it" do
        foreign = Component::Tabs.new.add_tab("Foreign")
        assert_raises(ArgumentError) { tabs.selected = foreign }
        assert_raises(ArgumentError) { tabs.remove_tab(foreign) }
      end
    end

    context "selection" do
      it "selects by tab and by index" do
        strip = tabs
        strip.selected = strip.tabs[2]
        assert_equal 2, strip.selected_index
        strip.selected_index = 1
        assert_equal strip.tabs[1], strip.selected
      end

      it "rejects a non-Integer or out-of-range index" do
        strip = tabs
        assert_raises(TypeError) { strip.selected_index = nil }
        assert_raises(TypeError) { strip.selected_index = "1" }
        assert_raises(ArgumentError) { strip.selected_index = 3 }
        assert_raises(ArgumentError) { strip.selected_index = -1 }
      end

      it "repaints the strip on a change" do
        strip = attached_tabs
        Screen.instance.invalidated_clear
        strip.selected_index = 2
        assert Screen.instance.invalidated?(strip)
      end
    end

    context "on_tab_selected" do
      it "fires when the first tab is added" do
        strip = Component::Tabs.new
        log = recorder(strip)
        strip.add_tab("First")
        strip.add_tab("Second")
        assert_equal [[0, "First"]], log
      end

      it "fires once per change, with the new index and tab" do
        strip = tabs
        log = recorder(strip)
        strip.selected_index = 2
        strip.selected = strip.tabs[1]
        assert_equal [[2, "Shipping"], [1, "Payment"]], log
      end

      it "does not fire when the selection ends up where it already was" do
        strip = tabs
        log = recorder(strip)
        strip.selected_index = 0
        strip.selected = strip.tabs.first
        assert_empty log
      end

      it "fires on the tab that slid into place when the selected tab is removed" do
        strip = tabs
        strip.selected_index = 1
        log = recorder(strip)
        strip.remove_tab(strip.tabs[1])
        # The index is unchanged — 1 now holds Shipping — so the notification
        # can't be decided by comparing indices.
        assert_equal [[1, "Shipping"]], log
      end

      it "fires on the new last tab when the selected tab was last" do
        strip = tabs
        strip.selected_index = 2
        log = recorder(strip)
        strip.remove_tab(strip.tabs[2])
        assert_equal [[1, "Payment"]], log
      end

      it "does not fire when a tab before the selection is removed, but tracks the shift" do
        strip = tabs
        strip.selected_index = 2
        log = recorder(strip)
        strip.remove_tab(strip.tabs[0])
        assert_empty log
        assert_equal 1, strip.selected_index
        assert_equal "Shipping", strip.selected.caption.to_s
      end

      it "does not fire when a tab after the selection is removed" do
        strip = tabs
        log = recorder(strip)
        strip.remove_tab(strip.tabs[2])
        assert_empty log
        assert_equal 0, strip.selected_index
      end

      it "fires with (nil, nil) when the last remaining tab is removed" do
        strip = tabs(captions: %w[Only])
        log = recorder(strip)
        strip.remove_tab(strip.tabs.first)
        assert_equal [[nil, nil]], log
        assert_nil strip.selected
        assert_nil strip.selected_index
      end
    end

    context "keys" do
      it "switches on LEFT and RIGHT, consuming the key" do
        strip = tabs
        assert strip.handle_key(Keys::RIGHT_ARROW)
        assert_equal 1, strip.selected_index
        assert strip.handle_key(Keys::LEFT_ARROW)
        assert_equal 0, strip.selected_index
      end

      it "clamps at both ends and still consumes the key" do
        strip = tabs
        assert strip.handle_key(Keys::LEFT_ARROW)
        assert_equal 0, strip.selected_index
        strip.selected_index = 2
        assert strip.handle_key(Keys::RIGHT_ARROW)
        assert_equal 2, strip.selected_index
      end

      it "declines the arrows on an empty strip, so they bubble" do
        strip = Component::Tabs.new
        refute strip.handle_key(Keys::LEFT_ARROW)
        refute strip.handle_key(Keys::RIGHT_ARROW)
      end

      it "declines Enter, Space, the vertical arrows, Home, End and printables" do
        strip = tabs
        keys = [Keys::ENTER, " ", Keys::UP_ARROW, Keys::DOWN_ARROW, "s"] + Keys::HOMES + Keys::ENDS_
        keys.each do |key|
          refute strip.handle_key(key), "expected #{key.inspect} to bubble"
        end
        assert_equal 0, strip.selected_index
      end

      it "hints the arrows only while it has tabs" do
        assert_includes tabs.keyboard_hint, "switch"
        assert_equal "", Component::Tabs.new.keyboard_hint
      end
    end

    context "mouse" do
      it "selects the tab under the click, padding column included" do
        strip = attached_tabs
        strip.handle_mouse(MouseEvent.new(:left, 11, 0)) # "Payment"'s first letter
        assert_equal 1, strip.selected_index
        strip.handle_mouse(MouseEvent.new(:left, 0, 0)) # "Details"' leading padding
        assert_equal 0, strip.selected_index
        strip.handle_mouse(MouseEvent.new(:left, 29, 0)) # "Shipping"'s trailing padding
        assert_equal 2, strip.selected_index
      end

      it "selects nothing on a separator column" do
        strip = attached_tabs
        strip.handle_mouse(MouseEvent.new(:left, 9, 0))
        assert_equal 0, strip.selected_index
      end

      it "selects nothing on the blank tail, but still focuses" do
        strip = attached_tabs
        strip.handle_mouse(MouseEvent.new(:left, 35, 0))
        assert_equal 0, strip.selected_index
        assert_equal strip, Screen.instance.focused
      end

      it "ignores a click on a row it does not paint" do
        strip = attached_tabs
        strip.rect = Rect.new(0, 0, 40, 3)
        strip.handle_mouse(MouseEvent.new(:left, 11, 2))
        assert_equal 0, strip.selected_index
      end

      it "ignores a non-left button" do
        strip = attached_tabs
        strip.handle_mouse(MouseEvent.new(:right, 11, 0))
        assert_equal 0, strip.selected_index
      end

      it "resolves a click against the current captions, not the last painted ones" do
        strip = attached_tabs
        strip.tabs.first.caption = "D" # segment 0 shrinks to 3 columns
        strip.handle_mouse(MouseEvent.new(:left, 5, 0)) # inside "Payment" now
        assert_equal 1, strip.selected_index
      end
    end

    context "scrolling" do
      # The strip painted at its natural 30 columns, for reference:
      #
      #   column  0         9        19        29
      #           ␣Details␣│␣Payment␣│␣Shipping␣
      def offset(strip) = strip.send(:left_column)

      def painted(strip)
        strip.repaint
        Screen.instance.buffer.region_text(strip.rect).join
      end

      it "does not scroll while the strip fits, wherever the selection is" do
        strip = tabs
        strip.selected_index = 2
        assert_equal 0, offset(strip)
        assert_equal " Details │ Payment │ Shipping           ", painted(strip)
      end

      it "scrolls the minimum needed to reveal the selection, and back again" do
        strip = tabs(width: 12)
        assert_equal 0, offset(strip)
        strip.selected_index = 1 # " Payment " ends at column 19
        assert_equal 7, offset(strip)
        assert_equal "< │ Payment>", painted(strip)
        strip.selected_index = 0
        assert_equal 0, offset(strip)
        assert_equal " Details │ >", painted(strip)
      end

      it "stops at the end of the strip, dropping the right cue with it" do
        strip = tabs(width: 12)
        strip.selected_index = 2
        assert_equal 18, offset(strip)
        assert_equal "<│ Shipping ", painted(strip)
      end

      it "shows the head of a caption wider than the whole rect, and settles there" do
        strip = tabs(width: 10, captions: %w[A VeryLongCaptionIndeed])
        strip.selected_index = 1
        assert_equal 4, offset(strip)
        assert_equal "<VeryLong>", painted(strip)
        strip.repaint
        assert_equal 4, offset(strip)
      end

      it "never opens the window on a wide glyph's right half" do
        strip = tabs(width: 7, captions: %w[本本本 ab])
        strip.selected_index = 1
        assert_equal 7, offset(strip) # 6 would open on the third 本's right half
        assert_equal "<│ ab  ", painted(strip)
        assert_equal 6, strip.extent.width
      end

      it "scrolls back when the rect grows, and re-clamps when the tabs shrink" do
        strip = tabs(width: 12)
        strip.selected_index = 2
        assert_equal 18, offset(strip)
        strip.rect = Rect.new(0, 0, 40, 1)
        assert_equal 0, offset(strip)
        strip.rect = Rect.new(0, 0, 12, 1)
        assert_equal 18, offset(strip)
        strip.tabs.last.remove # the selection lands on "Payment", and the strip is 19 columns
        assert_equal 7, offset(strip)
      end

      it "re-syncs when a caption changes width" do
        strip = tabs(width: 12)
        strip.selected_index = 1
        assert_equal 7, offset(strip)
        strip.tabs.first.caption = "D" # segment 0 shrinks by six columns
        assert_equal 4, offset(strip)
      end

      it "reveals a partially visible segment clicked at the edge" do
        strip = attached_tabs(width: 12)
        strip.handle_mouse(MouseEvent.new(:left, 11, 0)) # the cue column, over "Payment"'s "P"
        assert_equal 1, strip.selected_index
        assert_equal 7, offset(strip)
        assert_equal "< │ Payment>", painted(strip)
      end

      it "resolves a click against the scrolled strip, not the unscrolled one" do
        strip = attached_tabs(width: 12)
        strip.selected_index = 2 # offset 18, so column 0 paints strip column 18
        strip.handle_mouse(MouseEvent.new(:left, 1, 0)) # the separator: selects nothing
        assert_equal 2, strip.selected_index
        strip.handle_mouse(MouseEvent.new(:left, 0, 0)) # "Payment"'s trailing padding
        assert_equal 1, strip.selected_index
        assert_equal 10, offset(strip)
      end

      it "paints a cue in the style of the cell it covers" do
        strip = tabs(width: 12, active: true)
        strip.selected_index = 1
        strip.repaint
        cell = Screen.instance.buffer.cell(11, 0) # over "Payment"'s trailing padding
        assert_equal ">", cell.grapheme
        assert cell.style.bold
        assert_equal Screen.instance.theme.active_bg_color, cell.style.bg
      end
    end

    context "extent" do
      it "spans the segments and separators, one row" do
        assert_equal Rect.new(0, 0, 30, 1), tabs.extent
      end

      it "clips to a narrower rect" do
        assert_equal Rect.new(0, 0, 12, 1), tabs(width: 12).extent
      end

      it "is empty when there are no tabs" do
        strip = Component::Tabs.new
        strip.rect = Rect.new(0, 0, 40, 1)
        assert_equal 0, strip.extent.width
      end
    end

    context "repaint" do
      it "is a no-op when rect is empty" do
        Component::Tabs.new.repaint
        assert_empty Screen.instance.prints
      end

      it "pads each caption and joins with the separator" do
        strip = tabs
        strip.repaint
        assert_equal " Details │ Payment │ Shipping           ",
                     Screen.instance.buffer.region_text(strip.rect).join
      end

      it "clips the overflowing segment at the rect edge, cueing the rest" do
        strip = tabs(width: 12)
        strip.repaint
        assert_equal " Details │ >", Screen.instance.buffer.region_text(strip.rect).join
      end

      it "paints an empty strip as blank" do
        strip = Component::Tabs.new
        strip.rect = Rect.new(0, 0, 4, 1)
        strip.repaint
        assert_equal "    ", Screen.instance.buffer.region_text(strip.rect).join
      end

      it "uses a custom separator" do
        strip = tabs(captions: %w[A B])
        strip.separator = "|"
        strip.repaint
        assert_equal " A | B ", Screen.instance.buffer.region_text(strip.extent).join
      end

      it "refuses an empty separator" do
        assert_raises(ArgumentError) { Component::Tabs.new.separator = "" }
      end

      context "the selected segment" do
        it "is bold even when the strip is unfocused, and unselected ones are not" do
          strip = tabs(active: false)
          strip.selected_index = 1
          strip.repaint
          buffer = Screen.instance.buffer
          (10..18).each { |x| assert buffer.cell(x, 0).style.bold, "column #{x} should be bold" }
          [1, 9, 21].each { |x| refute buffer.cell(x, 0).style.bold, "column #{x} should not be bold" }
        end

        it "sits on active_bg_color only while the strip is on the focus chain" do
          strip = tabs(active: true)
          strip.selected_index = 1
          strip.repaint
          buffer = Screen.instance.buffer
          highlight = Screen.instance.theme.active_bg_color
          # The padding columns are part of the segment, so the highlight covers
          # them; the separator column beside them is chrome and stays clear.
          assert_equal highlight, buffer.cell(10, 0).style.bg
          assert_equal highlight, buffer.cell(18, 0).style.bg
          assert_nil buffer.cell(9, 0).style.bg
          assert_nil buffer.cell(19, 0).style.bg
        end

        it "carries no background while the strip is unfocused" do
          strip = tabs(active: false)
          strip.repaint
          assert_nil Screen.instance.buffer.cell(1, 0).style.bg
        end

        it "keeps the caption's own colors under the strip's styling" do
          strip = Component::Tabs.new
          strip.add_tab(StyledString.styled("Red", fg: :red))
          strip.rect = Rect.new(0, 0, 10, 1)
          strip.active = true
          strip.repaint
          cell = Screen.instance.buffer.cell(1, 0)
          assert_equal Color::RED, cell.style.fg
          assert cell.style.bold
          assert_equal Screen.instance.theme.active_bg_color, cell.style.bg
        end
      end

      it "measures double-width captions by display width" do
        strip = Component::Tabs.new
        strip.add_tab("日本")
        strip.add_tab("B")
        strip.rect = Rect.new(0, 0, 20, 1)
        strip.repaint
        assert_equal Rect.new(0, 0, 10, 1), strip.extent
        assert_equal " 日本 │ B ", Screen.instance.buffer.region_text(strip.extent).join
      end
    end

    context "thread confinement, inherited through invalidate" do
      # Runs `block` on a spawned thread. Anything other than a {Tuile::Error}
      # propagates out of `Thread#value`, so a real failure still surfaces.
      # @return [Tuile::Error, nil] the refusal, or nil if the block was allowed.
      def error_from(&block)
        Thread.new do
          block.call
          nil
        rescue Tuile::Error => e
          e
        end.value
      end

      it "refuses a mutation from another thread" do
        strip = attached_tabs
        assert_kind_of(Error, error_from { strip.add_tab("Nope") })
        assert_kind_of(Error, error_from { strip.selected_index = 2 })
        assert_kind_of(Error, error_from { strip.tabs.first.caption = "Nope" })
      end

      it "allows a detached strip to be assembled anywhere" do
        assert_nil(error_from { Component::Tabs.new.add_tab("Fine") })
      end
    end
  end
end
