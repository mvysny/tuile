# frozen_string_literal: true

module Tuile
  describe Component::Scroller do
    before { Screen.fake }
    after { Screen.close }

    let(:screen) { Screen.instance }

    let(:content) { Component::Layout::Absolute.new }

    # A scroller showing 5 rows of a 40-row content, wide enough for the bar to
    # take its two columns.
    def scroller(child = content, rows: 40, rect: Rect.new(0, 0, 10, 5))
      mount_at(Component::Scroller.new(child, content_rows: rows), rect)
    end

    context "the content child" do
      it "is as tall as content_rows and as wide as the viewport minus the bar" do
        scroller
        assert_equal Rect.new(0, 0, 8, 40), content.rect
      end

      it "fills the viewport when the content declares fewer rows" do
        scroller(rows: 2)
        assert_equal 5, content.rect.height
      end

      it "rises out of the scroller as it scrolls — the one negative rect" do
        scroller.scroll_top_row = 7
        content.flush_layout
        assert_equal Rect.new(0, -7, 8, 40), content.rect
      end

      it "is re-placed when the scroller moves" do
        Testing.place(scroller, Rect.new(0, 0, 20, 8))
        content.flush_layout
        assert_equal Rect.new(0, 0, 18, 40), content.rect
      end

      it "is placed on arrival, scroll included" do
        s = scroller(nil)
        s.scroll_top_row = 3
        s.content = content
        content.flush_layout
        assert_equal Rect.new(0, -3, 8, 40), content.rect
      end
    end

    context "content_rows" do
      it "refuses a negative count" do
        assert_raises(ArgumentError) { scroller.content_rows = -1 }
      end

      it "refuses a non-Integer" do
        assert_raises(ArgumentError) { scroller.content_rows = 3.5 }
      end

      it "pulls the scroll back when the content shrinks under it" do
        s = scroller
        s.scroll_top_row = 35
        s.content_rows = 10
        assert_equal 5, s.scroll_top_row
      end

      it "leaves the scroll alone when the content still reaches past it" do
        s = scroller
        s.scroll_top_row = 5
        s.content_rows = 30
        assert_equal 5, s.scroll_top_row
      end
    end

    context "scroll_top_row" do
      it "starts at the top" do
        assert_equal 0, scroller.scroll_top_row
      end

      it "refuses a negative row" do
        assert_raises(ArgumentError) { scroller.scroll_top_row = -1 }
      end

      it "invalidates the scroller, whose bar handle moved" do
        s = scroller
        screen.invalidated_clear
        s.scroll_top_row = 4
        s.flush_layout
        assert screen.invalidated?(s)
      end
    end

    context "the scroll verbs" do
      it "move half a viewport at a time" do
        s = scroller
        s.scroll_half_page_down
        assert_equal 2, s.scroll_top_row
      end

      it "clamp at the last row that still fills the viewport" do
        s = scroller
        20.times { s.scroll_half_page_down }
        assert_equal 35, s.scroll_top_row
      end

      it "clamp at the top" do
        s = scroller
        s.scroll_half_page_up
        assert_equal 0, s.scroll_top_row
      end

      it "do nothing when the content fits" do
        s = scroller(rows: 3)
        s.scroll_half_page_down
        assert_equal 0, s.scroll_top_row
      end
    end

    context "the wheel" do
      def notch(target, direction)
        target.handle_mouse_scroll?(Mouse::ScrollEvent.new(direction, 0, 0))
      end

      it "scrolls four rows a notch" do
        s = scroller
        assert notch(s, :down)
        assert_equal 4, s.scroll_top_row
      end

      it "declines at the end, so the notch bubbles to an outer scroller" do
        s = scroller
        s.scroll_top_row = 35
        refute notch(s, :down)
      end

      it "declines at the top" do
        refute notch(scroller, :up)
      end

      # The router owns the walk, so a notch over content that doesn't scroll
      # bubbles to the scroller with no hit test of its own.
      it "takes a notch the content under the pointer did not claim" do
        s = scroller(Component::Label.new("not a scroller"))

        screen.handle_mouse(Mouse::ScrollEvent.new(:down, 2, 2))

        assert_equal 4, s.scroll_top_row
      end
    end

    context "#scroll_to_visible" do
      # The rects below are in the scroller's own coordinates, which is where a
      # child's request arrives once the climb has converted it.
      it "does nothing for a rect already in the viewport" do
        s = scroller
        s.scroll_top_row = 10
        s.scroll_to_visible(Rect.new(0, 1, 8, 2))
        assert_equal 10, s.scroll_top_row
      end

      it "scrolls up the minimum for a rect above the viewport" do
        s = scroller
        s.scroll_top_row = 10
        s.scroll_to_visible(Rect.new(0, -3, 8, 1))
        assert_equal 7, s.scroll_top_row
      end

      it "scrolls down the minimum for a rect below the viewport" do
        s = scroller
        s.scroll_to_visible(Rect.new(0, 6, 8, 2))
        assert_equal 3, s.scroll_top_row
      end

      it "aligns the top of a rect too tall to fit" do
        s = scroller
        s.scroll_to_visible(Rect.new(0, 8, 8, 20))
        assert_equal 8, s.scroll_top_row
      end

      it "leaves a rect that already covers the viewport alone" do
        s = scroller
        s.scroll_top_row = 10
        s.scroll_to_visible(Rect.new(0, -2, 8, 20))
        assert_equal 10, s.scroll_top_row
      end

      it "clamps rather than scrolling past the end" do
        s = scroller
        s.scroll_to_visible(Rect.new(0, 100, 8, 1))
        assert_equal 35, s.scroll_top_row
      end

      # The half of the contract an outer scroller depends on: it is told where
      # the rect sits *after* this scroll, not where it sat when asked.
      it "passes the request up with the rect where its own scroll left it" do
        outer = Class.new(Component::Layout::Absolute) do
          attr_reader :requests

          def initialize
            super
            @requests = []
          end

          def scroll_to_visible(rect = local_extent_rect)
            @requests << rect
            super
          end
        end.new
        mount_at(outer, Rect.new(0, 0, 10, 5))
        s = Component::Scroller.new(Component::Layout::Absolute.new, content_rows: 40)
        outer.add(s)
        Testing.place(s, Rect.new(0, 0, 10, 5))

        s.scroll_to_visible(Rect.new(0, 6, 8, 2))

        assert_equal 3, s.scroll_top_row
        assert_equal [Rect.new(0, 3, 8, 2)], outer.requests
      end
    end

    context "focus" do
      # Ten one-row fields in a 5-row viewport, so half of them sit below the
      # fold — where they are tab stops like any other.
      def ten_fields
        form = Component::Layout::Vertical.new
        fields = Array.new(10) { Component::TextField.new }
        fields.each { form.add(_1, Component::Layout::Fixed[1]) }
        [scroller(form, rows: 10), fields]
      end

      it "brings a field below the fold into view" do
        s, fields = ten_fields

        screen.focused = fields.last

        assert_equal 5, s.scroll_top_row
        assert_equal Rect.new(0, 4, 8, 1), fields.last.absolute_rect
      end

      it "forwards focus into the content rather than keeping it" do
        s, fields = ten_fields

        s.focus

        assert_equal fields.first, screen.focused
      end

      # The promise the whole note was written for: nothing hides a scrolled-out
      # child, so Tab reaches the field below the fold and the view follows.
      it "follows Tab past the bottom of the viewport" do
        s, fields = ten_fields
        screen.focused = fields[4]

        screen.focus_next

        assert_equal fields[5], screen.focused
        assert_equal 1, s.scroll_top_row
        assert_equal Rect.new(0, 4, 8, 1), fields[5].absolute_rect
      end

      it "scrolls back up when focus returns to the top" do
        s, fields = ten_fields
        screen.focused = fields.last

        screen.focused = fields.first

        assert_equal 0, s.scroll_top_row
      end

      # The stale count: the form grew to ten rows, the scroller still says
      # seven, so the last fields are clipped and no scroll can reach them.
      it "logs a warning when a stale content_rows leaves the focused field out of reach" do
        log = StringIO.new
        saved = Tuile.logger
        Tuile.logger = Logger.new(log)
        s, fields = ten_fields
        s.content_rows = 7

        screen.focused = fields.last

        assert_equal 2, s.scroll_top_row
        assert_includes log.string, "shows nothing"
      ensure
        Tuile.logger = saved
      end
    end

    context "painting" do
      # Content that writes its own row index, so what the viewport shows says
      # which rows are on screen.
      def numbered_content
        Class.new(Component) do
          def repaint(canvas)
            height.times { canvas.set_text(0, _1, StyledString.plain("row#{_1}")) }
          end
        end.new
      end

      it "shows the rows the scroll offset selects, and nothing above them" do
        s = scroller(numbered_content)
        s.scroll_top_row = 7

        screen.repaint

        assert_equal ["row7 ", "row8 ", "row9 ", "row10", "row11"],
                     screen.buffer.region_text(Rect.new(0, 0, 5, 5))
      end

      it "paints the bar in the last column, over a blank reserve column" do
        scroller(numbered_content)

        screen.repaint

        assert_equal ["  █", "  ░", "  ░", "  ░", "  ░"],
                     screen.buffer.region_text(Rect.new(7, 0, 3, 5))
      end

      it "paints bare track when the content fits" do
        scroller(numbered_content, rows: 3)

        screen.repaint

        assert_equal %w[░ ░ ░ ░ ░], screen.buffer.region_text(Rect.new(9, 0, 1, 5))
      end

      it "gives the bar's columns back to the content when it is gone" do
        content = Component::Layout::Absolute.new
        s = scroller(content)
        s.scrollbar_visibility = :gone

        screen.repaint

        assert_equal 10, content.rect.width
        assert_equal "     ", screen.buffer.region_text(Rect.new(5, 0, 5, 1)).first
      end

      it "refuses a scrollbar_visibility it does not know" do
        assert_raises(ArgumentError) { scroller.scrollbar_visibility = :bogus }
      end

      context ":auto" do
        def auto_scroller(child, rows:, rect: Rect.new(0, 0, 10, 5))
          s = scroller(child, rows: rows, rect: rect)
          s.scrollbar_visibility = :auto
          s.flush_layout
          s
        end

        def bar(scroller) = Testing.get(Component::VerticalScrollBar, in: scroller)

        it "is accepted" do
          s = scroller
          s.scrollbar_visibility = :auto
          assert_equal :auto, s.scrollbar_visibility
        end

        it "hides the bar and hands the content the full width while it fits" do
          content = Component::Layout::Absolute.new
          s = auto_scroller(content, rows: 5)
          assert bar(s).rect.empty?
          assert_equal Rect.new(0, 0, 10, 5), content.rect
        end

        it "shows the bar and narrows the content once it overflows" do
          content = Component::Layout::Absolute.new
          s = auto_scroller(content, rows: 6)
          assert_equal Rect.new(9, 0, 1, 5), bar(s).rect
          assert_equal 8, content.rect.width
        end

        it "follows content_rows= across the threshold, both ways" do
          content = Component::Layout::Absolute.new
          s = auto_scroller(content, rows: 5)
          s.content_rows = 30
          s.flush_layout
          refute bar(s).rect.empty?
          assert_equal 8, content.rect.width
          s.content_rows = 3
          s.flush_layout
          assert bar(s).rect.empty?
          assert_equal 10, content.rect.width
        end

        it "follows a height-only resize across the threshold, both ways" do
          content = Component::Layout::Absolute.new
          s = auto_scroller(content, rows: 5)
          Testing.place(s, Rect.new(0, 0, 10, 4))
          s.flush_layout
          assert_equal Rect.new(9, 0, 1, 4), bar(s).rect
          assert_equal 8, content.rect.width
          Testing.place(s, Rect.new(0, 0, 10, 5))
          s.flush_layout
          assert bar(s).rect.empty?
          assert_equal 10, content.rect.width
        end

        it "paints the bar's column only while there is something to scroll" do
          s = auto_scroller(Component::Layout::Absolute.new, rows: 5)
          screen.repaint
          refute_match(/[█░]/, screen.buffer.region_text(s.absolute_rect).join)
          s.content_rows = 10
          screen.repaint
          assert_equal "█", screen.buffer.cell(9, 0).grapheme
        end
      end
    end

    context "the bar as a child" do
      # The bar is chrome, so it is appended: the content keeps index 0 and
      # with it the bottom of the paint order.
      it "sits after the content in the tree" do
        s = scroller
        assert_equal [content, Testing.get(Component::VerticalScrollBar, in: s)], s.children
      end

      it "takes the last column, the full height" do
        bar = Testing.get(Component::VerticalScrollBar, in: scroller)
        assert_equal Rect.new(9, 0, 1, 5), bar.rect
      end

      it "follows the scroller's resize" do
        s = scroller
        Testing.place(s, Rect.new(0, 0, 20, 8))
        Testing.get(Component::VerticalScrollBar, in: s).flush_layout
        assert_equal Rect.new(19, 0, 1, 8), Testing.get(Component::VerticalScrollBar, in: s).rect
      end

      it "is told the scroll state, not left to read it" do
        s = scroller
        s.scroll_top_row = 12
        Testing.get(Component::VerticalScrollBar, in: s).flush_layout
        bar = Testing.get(Component::VerticalScrollBar, in: s)
        assert_equal 12, bar.scroll_top_row
        assert_equal 40, bar.row_count
      end

      it "collapses to nothing when the bar is gone" do
        s = scroller
        s.scrollbar_visibility = :gone
        Testing.get(Component::VerticalScrollBar, in: s).flush_layout
        assert_equal Rect.new(0, 0, 0, 0), Testing.get(Component::VerticalScrollBar, in: s).rect
      end

      it "scrolls the content when the handle is dragged" do
        s = scroller

        screen.drag([9, 0], [9, 4])

        assert_equal 35, s.scroll_top_row
        assert_equal Rect.new(0, -35, 8, 40), content.rect
      end

      it "pages when the track is pressed" do
        s = scroller

        screen.press(9, 3)

        assert_equal 5, s.scroll_top_row
      end

      # The bar is chrome: pressing it must not take focus off what the user
      # was editing, which is what `focusable? == false` buys.
      it "leaves focus where it was" do
        field = Component::TextField.new
        scroller(field)
        screen.focused = field

        screen.press(9, 3)

        assert_equal field, screen.focused
      end

      it "hands the wheel over the bar to the scroller" do
        s = scroller

        screen.scroll(:down, 9, 2)

        assert_equal 4, s.scroll_top_row
      end
    end
  end
end
