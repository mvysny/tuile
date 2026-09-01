# frozen_string_literal: true

module Tuile
  describe VerticalScrollBar do
    context "height == 0" do
      it "constructor succeeds" do
        assert VerticalScrollBar.new(0, row_count: 0, scroll_top_row: 0)
      end

      it "does not set handle instance variables" do
        sb = VerticalScrollBar.new(0, row_count: 0, scroll_top_row: 0)
        assert_nil sb.handle_height
        assert_nil sb.handle_start
        assert_nil sb.handle_end
      end
    end

    context "height == 1" do
      let(:sb) { VerticalScrollBar.new(1, row_count: 10, scroll_top_row: 0) }

      it "returns █ for the only row" do
        assert_equal "█", sb.scrollbar_char(0)
      end

      it "sets handle to cover the single row" do
        assert_equal 1, sb.handle_height
        assert_equal 0, sb.handle_start
        assert_equal 0, sb.handle_end
      end
    end

    context "content fits (row_count <= height)" do
      let(:sb) { VerticalScrollBar.new(5, row_count: 3, scroll_top_row: 0) }

      it "draws no handle — a full-height one carries no information" do
        (0..4).each { |r| assert_equal "░", sb.scrollbar_char(r) }
      end

      it "draws no handle when the content exactly fills the viewport either" do
        exact = VerticalScrollBar.new(5, row_count: 5, scroll_top_row: 0)
        (0..4).each { |r| assert_equal "░", exact.scrollbar_char(r) }
      end

      it "draws the handle again as soon as one row overflows" do
        overflowing = VerticalScrollBar.new(5, row_count: 6, scroll_top_row: 0)
        assert_equal "█", overflowing.scrollbar_char(0)
      end

      it "sets handle_height to full height" do
        assert_equal 5, sb.handle_height
      end

      it "sets handle_start to 0" do
        assert_equal 0, sb.handle_start
      end

      it "sets handle_end to height - 1" do
        assert_equal 4, sb.handle_end
      end
    end

    context "content overflows: 20 lines, height 10, scroll_top_row 0" do
      let(:sb) { VerticalScrollBar.new(10, row_count: 20, scroll_top_row: 0) }

      it "computes handle_height" do
        assert_equal 5, sb.handle_height
      end

      it "sets handle_start to 0 when at top" do
        assert_equal 0, sb.handle_start
      end

      it "sets handle_end correctly" do
        assert_equal 4, sb.handle_end
      end

      it "shows handle at top of track" do
        (0..4).each { |r| assert_equal "█", sb.scrollbar_char(r) }
      end

      it "shows empty track below handle" do
        (5..9).each { |r| assert_equal "░", sb.scrollbar_char(r) }
      end
    end

    context "content overflows: 20 lines, height 10, scroll_top_row 10" do
      let(:sb) { VerticalScrollBar.new(10, row_count: 20, scroll_top_row: 10) }

      it "sets handle_start at middle of track" do
        assert_equal 5, sb.handle_start
      end

      it "sets handle_end at bottom of track" do
        assert_equal 9, sb.handle_end
      end

      it "shows empty track above handle" do
        (0..4).each { |r| assert_equal "░", sb.scrollbar_char(r) }
      end

      it "shows handle at bottom of track" do
        (5..9).each { |r| assert_equal "█", sb.scrollbar_char(r) }
      end
    end

    context "glyphs" do
      after do
        VerticalScrollBar.handle_char = "█"
        VerticalScrollBar.track_char = "░"
      end

      it "defaults to the block glyphs" do
        assert_equal "█", VerticalScrollBar.handle_char
        assert_equal "░", VerticalScrollBar.track_char
      end

      it "draws whatever the app assigned" do
        VerticalScrollBar.handle_char = "▐"
        VerticalScrollBar.track_char = "│"
        sb = VerticalScrollBar.new(10, row_count: 20, scroll_top_row: 0)
        assert_equal "▐", sb.scrollbar_char(0)
        assert_equal "│", sb.scrollbar_char(9)
      end

      it "uses the assigned track glyph for the nothing-to-scroll state too" do
        VerticalScrollBar.track_char = "│"
        sb = VerticalScrollBar.new(5, row_count: 3, scroll_top_row: 0)
        (0..4).each { |r| assert_equal "│", sb.scrollbar_char(r) }
      end

      it "rejects a non-String" do
        assert_raises(TypeError) { VerticalScrollBar.handle_char = :block }
      end

      it "rejects more than one grapheme cluster" do
        e = assert_raises(ArgumentError) { VerticalScrollBar.track_char = "ab" }
        assert_includes e.message, "track_char"
      end

      it "rejects a two-column glyph — it would push every row past rect.width" do
        e = assert_raises(ArgumentError) { VerticalScrollBar.handle_char = "🙂" }
        assert_includes e.message, "one column wide"
      end

      it "accepts a single combining cluster measuring one column" do
        VerticalScrollBar.handle_char = "é"
        assert_equal "é", VerticalScrollBar.handle_char
      end

      it "leaves the glyph frozen, so a caller cannot mutate it under the painter" do
        VerticalScrollBar.handle_char = +"▐"
        assert VerticalScrollBar.handle_char.frozen?
      end
    end

    context "handle_height is at least 1" do
      it "clamps handle to minimum height of 1 for large content" do
        sb = VerticalScrollBar.new(5, row_count: 1000, scroll_top_row: 0)
        assert_equal 1, sb.handle_height
      end
    end
  end
end
