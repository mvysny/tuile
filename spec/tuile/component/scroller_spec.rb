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
      Component::Scroller.new(child, content_rows: rows).tap do |s|
        screen.content = s
        s.rect = rect
      end
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
        assert_equal Rect.new(0, -7, 8, 40), content.rect
      end

      it "is re-placed when the scroller moves" do
        scroller.rect = Rect.new(0, 0, 20, 8)
        assert_equal Rect.new(0, 0, 18, 40), content.rect
      end

      it "is placed on arrival, scroll included" do
        s = scroller(nil)
        s.scroll_top_row = 3
        s.content = content
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
        screen.content = outer
        outer.rect = Rect.new(0, 0, 10, 5)
        s = Component::Scroller.new(Component::Layout::Absolute.new, content_rows: 40)
        outer.add(s)
        s.rect = Rect.new(0, 0, 10, 5)

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
        assert_raises(ArgumentError) { scroller.scrollbar_visibility = :auto }
      end
    end
  end
end
