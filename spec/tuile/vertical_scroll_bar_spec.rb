# frozen_string_literal: true

module Tuile
  describe VerticalScrollBar do
    context "height == 0" do
      it "constructor succeeds" do
        assert VerticalScrollBar.new(0, line_count: 0, top_line: 0)
      end

      it "does not set handle instance variables" do
        sb = VerticalScrollBar.new(0, line_count: 0, top_line: 0)
        assert_nil sb.handle_height
        assert_nil sb.handle_start
        assert_nil sb.handle_end
      end
    end

    context "height == 1" do
      let(:sb) { VerticalScrollBar.new(1, line_count: 10, top_line: 0) }

      it "returns █ for the only row" do
        assert_equal "█", sb.scrollbar_char(0)
      end

      it "sets handle to cover the single row" do
        assert_equal 1, sb.handle_height
        assert_equal 0, sb.handle_start
        assert_equal 0, sb.handle_end
      end
    end

    context "content fits (line_count <= height)" do
      let(:sb) { VerticalScrollBar.new(5, line_count: 3, top_line: 0) }

      it "fills entire track with handle" do
        (0..4).each { |r| assert_equal "█", sb.scrollbar_char(r) }
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

    context "content overflows: 20 lines, height 10, top_line 0" do
      let(:sb) { VerticalScrollBar.new(10, line_count: 20, top_line: 0) }

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

    context "content overflows: 20 lines, height 10, top_line 10" do
      let(:sb) { VerticalScrollBar.new(10, line_count: 20, top_line: 10) }

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

    context "handle_height is at least 1" do
      it "clamps handle to minimum height of 1 for large content" do
        sb = VerticalScrollBar.new(5, line_count: 1000, top_line: 0)
        assert_equal 1, sb.handle_height
      end
    end
  end
end
