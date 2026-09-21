# frozen_string_literal: true

module Tuile
  describe Component::VerticalScrollBar do
    before { Screen.fake }
    after { Screen.close }

    let(:screen) { Screen.instance }

    # A 5-row bar onto 40 rows of content: a one-row handle over four rows of
    # free track, so every number below is checkable by hand.
    def bar(rows: 40, top: 0, height: 5)
      Component::VerticalScrollBar.new(row_count: rows, scroll_top_row: top).tap do |b|
        screen.content = b
        b.rect = Rect.new(0, 0, 1, height)
      end
    end

    # The rows the bar requested, in order.
    def requests(target)
      [].tap { |log| target.on_scroll_request { log << _1.scroll_top_row } }
    end

    context "geometry" do
      it "sizes the handle to the fraction of the content in view" do
        assert_equal 1, bar.handle_height
        assert_equal 4, bar(rows: 8).handle_height
      end

      # Ceil, not floor: a sliver of content still deserves a row of handle.
      it "never shrinks the handle below one row" do
        assert_equal 1, bar(rows: 1000).handle_height
      end

      # The trap Ink walks into: 10 rows of handle in a 10-row track is full,
      # immovable, and lying — there is a row of content out of sight.
      it "caps the handle a row short of the track while there is anything to scroll" do
        assert_equal 9, bar(rows: 11, height: 10).handle_height
      end

      it "gives the whole track to the handle when the content fits" do
        assert_equal 5, bar(rows: 3).handle_height
        refute bar(rows: 3).scrollable?
      end

      it "puts the handle at the top at row zero" do
        assert_equal 0, bar.handle_start
      end

      # The half Ink gets wrong: it maps over the whole track rather than the
      # free part, so the last rows of content never move the handle.
      it "puts the handle's last row at the foot of the track at the last row" do
        b = bar(top: 35)
        assert_equal 4, b.handle_start
        assert_equal 5, b.handle_start + b.handle_height
      end

      it "moves the handle proportionally in between" do
        assert_equal 2, bar(top: 18).handle_start
      end

      it "answers for an empty rect rather than dividing by its height" do
        b = bar(height: 0)
        assert_equal 0, b.handle_height
        assert_equal 0, b.handle_start
        refute b.scrollable?
      end
    end

    context "painting" do
      def painted(target)
        screen.repaint
        screen.buffer.region_text(target.absolute_rect)
      end

      it "draws the handle over the track" do
        assert_equal %w[░ ░ █ ░ ░], painted(bar(top: 18))
      end

      it "draws bare track when the content fits, the handle carrying nothing" do
        assert_equal %w[░ ░ ░ ░ ░], painted(bar(rows: 3))
      end

      context "with the glyphs swapped app-wide" do
        after do
          Component::VerticalScrollBar.handle_char = "█"
          Component::VerticalScrollBar.track_char = "░"
        end

        it "honours the pair" do
          Component::VerticalScrollBar.handle_char = "▐"
          Component::VerticalScrollBar.track_char = "│"
          assert_equal %w[▐ │ │ │ │], painted(bar)
        end

        it "uses the assigned track glyph for the nothing-to-scroll state too" do
          Component::VerticalScrollBar.track_char = "│"
          assert_equal %w[│ │ │ │ │], painted(bar(rows: 3))
        end
      end

      it "paints one column however wide a rect it is handed" do
        b = bar
        b.rect = Rect.new(0, 0, 4, 5)

        screen.repaint

        assert_equal Size.new(1, 5), b.extent
        assert_equal ["█   "], screen.buffer.region_text(Rect.new(0, 0, 4, 1))
      end
    end

    context "pressing the track" do
      it "pages down below the handle" do
        b = bar
        log = requests(b)

        screen.press(0, 3)

        assert_equal [5], log
      end

      it "pages up above the handle" do
        b = bar(top: 20)
        log = requests(b)

        screen.press(0, 0)

        assert_equal [15], log
      end

      it "clamps at the last row rather than asking for one past it" do
        b = bar(top: 30)
        log = requests(b)

        screen.press(0, 4)

        assert_equal [35], log
      end

      it "asks for nothing when there is nowhere to go" do
        b = bar(rows: 3)
        log = requests(b)

        screen.press(0, 4)

        assert_empty log
      end

      it "claims the press, so the drag that follows is its own" do
        assert bar.handle_mouse_down?(Mouse::DownEvent.new(:left, 0, 3))
      end

      it "leaves a right-click alone" do
        refute bar.handle_mouse_down?(Mouse::DownEvent.new(:right, 0, 3))
      end
    end

    context "dragging the handle" do
      it "reaches the last row" do
        b = bar
        log = requests(b)

        screen.drag([0, 0], [0, 4])

        assert_equal 35, log.last
      end

      it "reaches the first row again" do
        b = bar(top: 35)
        log = requests(b)

        screen.drag([0, 4], [0, 0])

        assert_equal 0, log.last
      end

      # The whole reason the drag is relative: the handle of a bar scrolled to
      # row 7 sits at row 1, and row 1 maps back to row 9 — so an absolute drag
      # would jerk the content two rows on a press that never moved.
      it "asks for nothing when the pointer does not move" do
        b = bar(top: 7)
        log = requests(b)

        screen.drag([0, 1], [0, 1])

        assert_empty log
      end

      it "scrolls by how far the pointer moved, from where the press found it" do
        b = bar(top: 7)
        log = requests(b)

        screen.drag([0, 1], [0, 2])

        assert_equal [16], log # 7 + one row of track, worth 8.75 rows of content
      end

      it "clamps a drag past the end of the track" do
        b = bar
        log = requests(b)

        screen.drag([0, 0], [0, 40])

        assert_equal 35, log.last
      end

      it "ignores a drag that began on the track, the press having paged already" do
        b = bar
        log = requests(b)

        screen.drag([0, 3], [0, 4])

        assert_equal [5], log # the page, and nothing from the move
      end

      it "does not drag a bar whose content fits" do
        b = bar(rows: 3)
        log = requests(b)

        screen.drag([0, 0], [0, 4])

        assert_empty log
      end
    end

    context "who owns the scroll position" do
      it "does not move itself — an unwired bar is inert" do
        b = bar

        screen.drag([0, 0], [0, 4])

        assert_equal 0, b.scroll_top_row
        assert_equal 0, b.handle_start
      end

      it "moves once the owner assigns what it asked for" do
        b = bar
        b.on_scroll_request { b.scroll_top_row = _1.scroll_top_row }

        screen.drag([0, 0], [0, 4])

        assert_equal 35, b.scroll_top_row
        assert_equal 4, b.handle_start
      end

      it "fires nothing from scroll_top_row=, so an owner assigning back loops nothing" do
        b = bar
        log = requests(b)

        b.scroll_top_row = 12

        assert_empty log
      end

      it "invalidates when either number moves" do
        b = bar
        screen.invalidated_clear
        b.scroll_top_row = 4
        assert screen.invalidated?(b)

        screen.invalidated_clear
        b.row_count = 50
        assert screen.invalidated?(b)
      end

      it "stays quiet on a no-op set" do
        b = bar
        screen.invalidated_clear
        b.scroll_top_row = 0
        refute screen.invalidated?(b)
      end

      it "refuses a negative or non-Integer row" do
        assert_raises(ArgumentError) { bar.row_count = -1 }
        assert_raises(ArgumentError) { bar.scroll_top_row = 2.5 }
        assert_raises(ArgumentError) { Component::VerticalScrollBar.new(row_count: -1) }
      end
    end

    # Clicking chrome must not take focus off the field the user was editing.
    it "is no focus target" do
      refute bar.focusable?
      refute bar.tab_stop?
    end

    it "declines the wheel, so the notch reaches whatever it scrolls" do
      refute bar.handle_mouse_scroll?(Mouse::ScrollEvent.new(:down, 0, 0))
    end

    # The app-global pair, validated at assignment because the symptom of a
    # wide glyph is a corrupt frame with nothing to point at (`D_scrollbar_ink`).
    context "the glyph knobs" do
      after do
        Component::VerticalScrollBar.handle_char = "█"
        Component::VerticalScrollBar.track_char = "░"
      end

      it "defaults to the block glyphs" do
        assert_equal "█", Component::VerticalScrollBar.handle_char
        assert_equal "░", Component::VerticalScrollBar.track_char
      end

      it "rejects a non-String" do
        assert_raises(TypeError) { Component::VerticalScrollBar.handle_char = :block }
      end

      it "rejects more than one grapheme cluster" do
        e = assert_raises(ArgumentError) { Component::VerticalScrollBar.track_char = "ab" }
        assert_includes e.message, "track_char"
      end

      it "rejects a two-column glyph — it would spill onto the content beside the bar" do
        e = assert_raises(ArgumentError) { Component::VerticalScrollBar.handle_char = "🙂" }
        assert_includes e.message, "one column wide"
      end

      it "accepts a single combining cluster measuring one column" do
        Component::VerticalScrollBar.handle_char = "é"
        assert_equal "é", Component::VerticalScrollBar.handle_char
      end

      it "leaves the glyph frozen, so a caller cannot mutate it under the painter" do
        Component::VerticalScrollBar.handle_char = +"▐"
        assert Component::VerticalScrollBar.handle_char.frozen?
      end
    end
  end
end
