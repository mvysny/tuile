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
      assert_equal ["\e[1;1H", "     ", "\e[1;1H", "1"], Screen.instance.prints
    end

    it "prints multiple lines within rect height" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 10, 3)
      label.text = "foo\nbar\nbaz"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "          ",
                    TTY::Cursor.move_to(0, 1), "          ",
                    TTY::Cursor.move_to(0, 2), "          ",
                    TTY::Cursor.move_to(0, 0), "foo",
                    TTY::Cursor.move_to(0, 1), "bar",
                    TTY::Cursor.move_to(0, 2), "baz"], Screen.instance.prints
    end

    it "clips lines vertically when text has more lines than height" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 10, 2)
      label.text = "one\ntwo\nthree"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "          ",
                    TTY::Cursor.move_to(0, 1), "          ",
                    TTY::Cursor.move_to(0, 0), "one",
                    TTY::Cursor.move_to(0, 1), "two"], Screen.instance.prints
    end

    it "truncates lines longer than rect width" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "hello world"
      label.repaint
      assert_equal [TTY::Cursor.move_to(0, 0), "     ",
                    TTY::Cursor.move_to(0, 0), "hell…"], Screen.instance.prints
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
      assert_equal [TTY::Cursor.move_to(0, 0), "     ",
                    TTY::Cursor.move_to(0, 0), "hell…"],
                   Screen.instance.prints
    end

    it "on_tree calls block on itself" do
      label = Component::Label.new
      visited = []
      label.on_tree { visited << it }
      assert_equal [label], visited
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
