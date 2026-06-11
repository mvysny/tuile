# frozen_string_literal: true

module Tuile
  describe Buffer do
    def buf(width, height) = Buffer.new(Size.new(width, height))

    describe ".new" do
      it "fills with blank cells and starts clean" do
        b = buf(3, 2)
        assert_equal Size.new(3, 2), b.size
        assert_equal 3, b.width
        assert_equal 2, b.height
        assert_equal Buffer::BLANK, b.cell(0, 0)
        assert_equal " ", b.cell(2, 1).grapheme
        refute b.dirty?
      end

      it "rejects a non-Size" do
        assert_raises(TypeError) { Buffer.new(5) }
      end
    end

    describe "#cell" do
      it "returns nil out of bounds" do
        b = buf(2, 2)
        assert_nil b.cell(-1, 0)
        assert_nil b.cell(2, 0)
        assert_nil b.cell(0, 2)
      end
    end

    describe "#set_char" do
      it "writes a grapheme and marks it dirty" do
        b = buf(3, 1)
        b.set_char(1, 0, "x")
        assert_equal "x", b.cell(1, 0).grapheme
        assert b.dirty?
      end

      it "does not mark a cell dirty when the value is unchanged" do
        b = buf(3, 1)
        b.set_char(0, 0, " ") # same as the blank it already holds
        refute b.dirty?
      end

      it "carries the style" do
        b = buf(2, 1)
        b.set_char(0, 0, "a", StyledString::Style.new(fg: :red))
        assert_equal Color::RED, b.cell(0, 0).style.fg
      end

      it "ignores out-of-bounds writes" do
        b = buf(2, 1)
        b.set_char(5, 0, "z")
        b.set_char(0, 3, "z")
        refute b.dirty?
      end

      it "ignores zero-width input (lone combining mark)" do
        b = buf(2, 1)
        b.set_char(0, 0, "́") # combining acute accent, width 0
        refute b.dirty?
      end
    end

    describe "wide characters" do
      it "occupies an origin cell plus a continuation" do
        b = buf(4, 1)
        b.set_char(0, 0, "世")
        assert_equal "世", b.cell(0, 0).grapheme
        assert b.cell(1, 0).continuation?
        assert_equal "世  ", b.row_text(0) # continuation contributes nothing; 2 trailing blanks
      end

      it "blanks a wide glyph that would overflow the last column" do
        b = buf(3, 1)
        b.set_char(2, 0, "世")
        assert_equal " ", b.cell(2, 0).grapheme
        refute b.cell(2, 0).continuation?
      end

      it "blanks the right half when its left half is overwritten" do
        b = buf(4, 1)
        b.set_char(0, 0, "世")
        b.set_char(0, 0, "a")
        assert_equal "a", b.cell(0, 0).grapheme
        assert_equal " ", b.cell(1, 0).grapheme
        refute b.cell(1, 0).continuation?
      end

      it "blanks the left half when its right (continuation) half is overwritten" do
        b = buf(4, 1)
        b.set_char(0, 0, "世")
        b.set_char(1, 0, "a")
        assert_equal " ", b.cell(0, 0).grapheme
        assert_equal "a", b.cell(1, 0).grapheme
      end

      it "emits the glyph once and nothing for the continuation" do
        b = buf(4, 1)
        b.set_char(0, 0, "世")
        assert_equal "\e[1;1H世", b.flush
      end
    end

    describe "#set_line" do
      it "writes graphemes left to right" do
        b = buf(6, 1)
        b.set_line(1, 0, StyledString.plain("hi"))
        assert_equal " hi   ", b.row_text(0)
      end

      it "clips at the right edge" do
        b = buf(5, 1)
        b.set_line(3, 0, StyledString.plain("hello"))
        assert_equal "   he", b.row_text(0)
      end

      it "preserves per-span styles" do
        b = buf(4, 1)
        b.set_line(0, 0, StyledString.styled("hi", fg: :red))
        assert_equal Color::RED, b.cell(0, 0).style.fg
        assert_equal Color::RED, b.cell(1, 0).style.fg
      end

      it "advances by display width across wide glyphs" do
        b = buf(6, 1)
        b.set_line(0, 0, StyledString.plain("世a"))
        assert_equal "世", b.cell(0, 0).grapheme
        assert b.cell(1, 0).continuation?
        assert_equal "a", b.cell(2, 0).grapheme
      end
    end

    describe "#fill / #clear" do
      it "fills the rect intersection with blanks of the given style" do
        b = buf(4, 3)
        b.set_char(0, 0, "x")
        b.fill(Rect.new(0, 0, 2, 2), StyledString::Style.new(bg: :blue))
        assert_equal " ", b.cell(0, 0).grapheme
        assert_equal Color::BLUE, b.cell(0, 0).style.bg
        assert_equal Color::BLUE, b.cell(1, 1).style.bg
        assert_equal Buffer::BLANK, b.cell(2, 0) # outside the fill rect
      end

      it "clips a fill rect to the buffer bounds" do
        b = buf(2, 2)
        b.fill(Rect.new(-1, -1, 10, 10), StyledString::Style.new(bg: :red))
        assert_equal Color::RED, b.cell(0, 0).style.bg
        assert_equal Color::RED, b.cell(1, 1).style.bg
      end

      it "clears the whole buffer" do
        b = buf(3, 2)
        b.set_char(1, 1, "x")
        b.clear
        assert_equal " ", b.cell(1, 1).grapheme
      end
    end

    describe "#flush" do
      it "returns empty when nothing changed" do
        assert_equal "", buf(3, 1).flush
      end

      it "emits move_to plus the changed grapheme" do
        b = buf(3, 1)
        b.set_char(0, 0, "a")
        assert_equal "\e[1;1Ha", b.flush
      end

      it "emits minimal SGR and resets at the end" do
        b = buf(2, 1)
        red = StyledString::Style.new(fg: :red)
        b.set_char(0, 0, "a", red)
        expected = "\e[1;1H#{StyledString::Style::DEFAULT.sgr_to(red)}a#{Ansi::RESET}"
        assert_equal expected, b.flush
      end

      it "groups adjacent dirty cells into one run but splits across a gap" do
        b = buf(5, 1)
        b.set_char(0, 0, "a")
        b.set_char(1, 0, "b")
        b.set_char(3, 0, "c") # gap at column 2
        out = b.flush
        assert_equal "#{TTY::Cursor.move_to(0, 0)}ab#{TTY::Cursor.move_to(3, 0)}c", out
      end

      it "only emits cells that actually changed" do
        b = buf(4, 1)
        b.set_char(2, 0, "z")
        assert_equal "#{TTY::Cursor.move_to(2, 0)}z", b.flush
      end

      it "addresses each dirty row separately" do
        b = buf(2, 2)
        b.set_char(0, 0, "a")
        b.set_char(1, 1, "b")
        assert_equal "#{TTY::Cursor.move_to(0, 0)}a#{TTY::Cursor.move_to(1, 1)}b", b.flush
      end

      it "clears the dirty set so a second flush is empty" do
        b = buf(3, 1)
        b.set_char(0, 0, "a")
        refute b.flush.empty?
        refute b.dirty?
        assert_equal "", b.flush
      end
    end

    describe "#mark_all_dirty" do
      it "forces the whole grid to re-emit" do
        b = buf(2, 1)
        b.flush # nothing dirty
        b.mark_all_dirty
        assert b.dirty?
        assert_equal "#{TTY::Cursor.move_to(0, 0)}  ", b.flush # two blanks
      end
    end

    describe "#resize" do
      it "changes dimensions, blanks cells, and marks all dirty" do
        b = buf(3, 2)
        b.set_char(0, 0, "x")
        b.flush
        b.resize(Size.new(2, 2))
        assert_equal Size.new(2, 2), b.size
        assert_equal " ", b.cell(0, 0).grapheme
        assert b.dirty?
      end

      it "rejects a non-Size" do
        assert_raises(TypeError) { buf(2, 2).resize(7) }
      end
    end

    describe "#row_text" do
      it "returns empty for an out-of-range row" do
        assert_equal "", buf(2, 2).row_text(5)
      end
    end
  end
end
