# frozen_string_literal: true

module Tuile
  describe Component::Label do
    before { Screen.fake }
    after { Screen.close }

    it "smokes" do
      label = Component::Label.new
      label.text = "Test 1 2 3 4"
    end

    it "accepts initial text in the constructor" do
      label = Component::Label.new("hi")
      assert_equal StyledString.parse("hi"), label.text
    end

    it "constructs empty when given no text" do
      assert_equal StyledString::EMPTY, Component::Label.new.text
    end

    it "accepts a StyledString in the constructor" do
      styled = StyledString.parse("hi")
      assert_equal styled, Component::Label.new(styled).text
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
      assert_equal ["     "], Screen.instance.buffer.region_text(label.rect)
    end

    it "prints only first line when height is 1" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "1\n2\n3"
      label.repaint
      assert_equal ["1    "], Screen.instance.buffer.region_text(label.rect)
    end

    it "prints multiple lines within rect height" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 10, 3)
      label.text = "foo\nbar\nbaz"
      label.repaint
      assert_equal ["foo       ", "bar       ", "baz       "], Screen.instance.buffer.region_text(label.rect)
    end

    it "clips lines vertically when text has more lines than height" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 10, 2)
      label.text = "one\ntwo\nthree"
      label.repaint
      assert_equal ["one       ", "two       "], Screen.instance.buffer.region_text(label.rect)
    end

    it "pads rows past the last text line with blanks" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 3)
      label.text = "hi"
      label.repaint
      assert_equal ["hi   ", "     ", "     "], Screen.instance.buffer.region_text(label.rect)
    end

    it "truncates lines longer than rect width" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = "hello world"
      label.repaint
      assert_equal ["hell…"], Screen.instance.buffer.region_text(label.rect)
    end

    it "handles nil text gracefully" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 5, 1)
      label.text = nil
      label.repaint
      assert_equal ["     "], Screen.instance.buffer.region_text(label.rect)
    end

    it "re-clips text when width changes" do
      label = Component::Label.new
      label.rect = Rect.new(0, 0, 3, 1)
      label.text = "hello world"
      label.rect = Rect.new(0, 0, 5, 1)
      label.repaint
      assert_equal ["hell…"], Screen.instance.buffer.region_text(label.rect)
    end

    it "on_tree calls block on itself" do
      label = Component::Label.new
      visited = []
      label.on_tree { visited << _1 }
      assert_equal [label], visited
    end

    describe "#text=" do
      it "accepts a String and parses embedded ANSI" do
        label = Component::Label.new
        label.text = "\e[31mhi\e[0m"
        assert_instance_of StyledString, label.text
        assert_equal "hi", label.text.to_s
        assert_equal Color::RED, label.text.spans.first.style.fg
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
        assert_equal ["\e[31mhi\e[0m   "], Screen.instance.buffer.region_ansi(label.rect)
      end

      it "preserves styling through ellipsis truncation" do
        label = Component::Label.new
        label.rect = Rect.new(0, 0, 5, 1)
        label.text = StyledString.styled("hello world", fg: :red)
        label.repaint
        # ellipsize keeps spans on the surviving chars; the default ellipsis
        # is plain, so it lands after the SGR reset.
        assert_equal ["\e[31mhell\e[0m…"], Screen.instance.buffer.region_ansi(label.rect)
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

    describe "inherited bg_color" do
      it "fills padding from an ancestor's bg_color when #bg is unset" do
        parent = Component::Layout::Absolute.new
        label = Component::Label.new("hi")
        parent.add(label)
        label.rect = Rect.new(0, 0, 5, 1)
        parent.bg_color = 52
        label.repaint
        assert_equal Color.new(52), Screen.instance.buffer.cell(0, 0).style.bg, "glyph cell"
        assert_equal Color.new(52), Screen.instance.buffer.cell(4, 0).style.bg, "padding cell"
      end

      it "lets its own bg_color override an inherited one" do
        parent = Component::Layout::Absolute.new
        label = Component::Label.new("hi")
        parent.add(label)
        label.rect = Rect.new(0, 0, 5, 1)
        parent.bg_color = 52
        label.bg_color = 22
        label.repaint
        assert_equal Color.new(22), Screen.instance.buffer.cell(0, 0).style.bg
      end

      it "paints its bg_color across text and pad" do
        label = Component::Label.new("hi")
        Screen.instance.content = label
        label.rect = Rect.new(0, 0, 5, 1)
        label.bg_color = :red
        label.repaint
        assert_equal ["\e[41mhi   \e[0m"], Screen.instance.buffer.region_ansi(label.rect)
      end

      it "paints its bg_color across blank rows past the last text line" do
        label = Component::Label.new("hi")
        Screen.instance.content = label
        label.rect = Rect.new(0, 0, 3, 2)
        label.bg_color = :red
        label.repaint
        assert_equal ["\e[41mhi \e[0m", "\e[41m   \e[0m"], Screen.instance.buffer.region_ansi(label.rect)
      end

      it "fills behind a styled span without dropping its fg" do
        label = Component::Label.new(StyledString.styled("hi", fg: :green))
        Screen.instance.content = label
        label.rect = Rect.new(0, 0, 4, 1)
        label.bg_color = :red
        label.repaint
        assert_equal ["\e[32;41mhi\e[39m  \e[0m"], Screen.instance.buffer.region_ansi(label.rect)
      end

      # The one thing #bg did that bg_color does not: stomp a span's own
      # background. That is a restyle of the text, so it belongs on the text.
      it "leaves a span's own background alone — with_bg on the text is the way" do
        label = Component::Label.new(StyledString.styled("hi", bg: :blue))
        Screen.instance.content = label
        label.rect = Rect.new(0, 0, 4, 1)
        label.bg_color = :red
        label.repaint
        assert_equal Color::BLUE, Screen.instance.buffer.cell(0, 0).style.bg
        assert_equal Color::RED, Screen.instance.buffer.cell(3, 0).style.bg # the pad

        label.text = label.text.with_bg(:red)
        label.repaint
        assert_equal Color::RED, Screen.instance.buffer.cell(0, 0).style.bg
      end
    end
  end
end
