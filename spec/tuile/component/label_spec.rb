# frozen_string_literal: true

module Tuile
  describe Component::Label do
    before { Screen.fake }
    after { Screen.close }

    it "smokes" do
      label = Component::Label.new
      label.text = "Test 1 2 3 4"
    end

    it "can repaint on unset text" do
      label = Component::Label.new
      label.repaint
      assert_equal [], Screen.instance.prints
    end

    it "clears background when text is empty" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.repaint
      assert_equal ["\e[1;1H", "     "], Screen.instance.prints
    end

    it "prints only first line when height is 1" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "1\n2\n3"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "1    "], Screen.instance.prints
    end

    it "prints multiple lines within rect height" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 10, 3)
      label.text = "foo\nbar\nbaz"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "foo       ",
                    TTY::Cursor.move_to(0, 1), "bar       ",
                    TTY::Cursor.move_to(0, 2), "baz       "], Screen.instance.prints
    end

    it "clips lines vertically when text has more lines than height" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 10, 2)
      label.text = "one\ntwo\nthree"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "one       ",
                    TTY::Cursor.move_to(0, 1), "two       "], Screen.instance.prints
    end

    it "pads rows past the last text line with blanks" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 3)
      label.text = "hi"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "hi   ",
                    TTY::Cursor.move_to(0, 1), "     ",
                    TTY::Cursor.move_to(0, 2), "     "], Screen.instance.prints
    end

    it "truncates lines longer than rect width" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "hello world"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "hell…"], Screen.instance.prints
    end

    it "handles nil text gracefully" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = nil
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "     "], Screen.instance.prints
    end

    it "re-clips text when width changes" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 3, 1)
      label.text = "hello world"
      label.rect = Rect.new(0, 0, 5, 1)
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "hell…"], Screen.instance.prints
    end

    it "on_tree calls block on itself" do
      label = Component::Label.new
      visited = []
      label.on_tree { visited << it }
      assert_equal [label], visited
    end

    describe "#text=" do
      it "accepts a String and parses embedded ANSI" do
        label = Component::Label.new
        label.text = "\e[31mhi\e[0m"
        assert_instance_of StyledString, label.text
        assert_equal "hi", label.text.to_s
        assert_equal :red, label.text.spans.first.style.fg
      end

      it "accepts a StyledString directly" do
        label = Component::Label.new
        styled = StyledString.styled("hi", fg: :green)
        label.text = styled
        assert_equal styled, label.text
      end

      it "coerces nil to an empty StyledString" do
        label = Component::Label.new
        label.text = nil
        assert label.text.empty?
      end

      it "preserves styling through paint" do
        label = Component::Label.new
        label.rect = Rect.new(0, 0, 5, 1)
        label.text = StyledString.styled("hi", fg: :red)
        label.repaint
        # styled "hi" padded to 5 cols: red "hi" then default-style spaces
        assert_equal [TTY::Cursor.move_to(0, 0), "\e[31mhi\e[0m   "], Screen.instance.prints
      end

      it "preserves styling through ellipsis truncation" do
        label = Component::Label.new
        label.rect = Rect.new(0, 0, 5, 1)
        label.text = StyledString.styled("hello world", fg: :red)
        label.repaint
        # ellipsize keeps spans on the surviving chars; the default ellipsis
        # is plain, so it lands after the SGR reset.
        assert_equal [TTY::Cursor.move_to(0, 0), "\e[31mhell\e[0m…"], Screen.instance.prints
      end
    end

    describe "#content_size" do
      it "returns zero width and height when text is empty" do
        label = Component::Label.new
        assert_equal Size.new(0, 0), label.content_size
      end

      it "returns height equal to number of lines" do
        label = Component::Label.new
        label.text = "one\ntwo\nthree"
        assert_equal 3, label.content_size.height
      end

      it "returns width equal to the longest ASCII line" do
        label = Component::Label.new
        label.text = "hi\nhello\nbye"
        assert_equal 5, label.content_size.width
      end

      it "returns width in columns for wide (fullwidth) characters" do
        label = Component::Label.new
        label.text = "日本語" # 3 wide chars = 6 columns
        assert_equal 6, label.content_size.width
      end

      it "excludes ANSI formatting from width" do
        label = Component::Label.new
        label.text = "\e[31mhello\e[0m" # "hello" = 5 columns
        assert_equal 5, label.content_size.width
      end

      it "height is not clamped to rect height" do
        label = Component::Label.new
        label.rect = Rect.new(0, 0, 20, 1)
        label.text = "one\ntwo\nthree"
        assert_equal 3, label.content_size.height
      end
    end

    it "does not invalidate when text is set to the same value again" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "hi"
      invalidated = Screen.instance.instance_variable_get(:@invalidated)
      invalidated.clear
      label.text = "hi"
      assert !invalidated.include?(label)
    end
  end
end
