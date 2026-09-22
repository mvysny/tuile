# frozen_string_literal: true

module Tuile
  describe Component::Fill do
    before { Screen.fake }
    after { Screen.close }

    def fill(char = "│", width: 1, height: 3, **kwargs)
      f = Component::Fill.new(char, **kwargs)
      Testing.place(f, Rect.new(0, 0, width, height))
      f
    end

    def attached_fill(char = "│", **kwargs)
      layout = Component::Layout::Absolute.new
      Screen.instance.content = layout
      fill(char, **kwargs).tap { layout.add(_1) }
    end

    it "is display-only: not focusable, not a tab stop" do
      f = Component::Fill.new("│")
      assert !f.focusable?
      assert !f.tab_stop?
    end

    it "paints a vertical rule down a one-column rect" do
      assert_equal %w[│ │ │], Testing.paint(fill).text
    end

    it "paints a horizontal rule across a one-row rect" do
      assert_equal ["─────"], Testing.paint(fill("─", width: 5, height: 1)).text
    end

    it "fills every cell of a larger rect" do
      assert_equal %w[░░░ ░░░], Testing.paint(fill("░", width: 3, height: 2)).text
    end

    it "paints the glyph in color" do
      painted = Testing.paint(fill(color: Color::GREEN))
      assert_equal Color::GREEN, painted.cell(0, 2).style.fg
    end

    it "defaults to the terminal's foreground" do
      assert_nil fill.color
      assert_nil Testing.paint(fill).cell(0, 0).style.fg
    end

    it "shows an ancestor's bg_color behind the glyph" do
      layout = Component::Layout::Absolute.new
      layout.bg_color = Color::BLUE
      Screen.instance.content = layout
      f = fill.tap { layout.add(_1) }
      assert_equal Color::BLUE, Testing.paint(f).cell(0, 0).style.bg
    end

    context "char" do
      it "repaints with a new glyph" do
        f = fill
        f.char = "┃"
        assert_equal %w[┃ ┃ ┃], Testing.paint(f).text
      end

      it "rejects a non-String" do
        assert_raises(TypeError) { Component::Fill.new(:bar) }
      end

      it "rejects more than one grapheme cluster" do
        e = assert_raises(ArgumentError) { fill.char = "||" }
        assert_includes e.message, "char"
      end

      it "rejects a two-column glyph" do
        e = assert_raises(ArgumentError) { Component::Fill.new("日") }
        assert_includes e.message, "one column wide"
      end
    end

    context "color" do
      it "re-resolves a Theme::Ref after a theme change" do
        f = attached_fill(color: Theme.ref(:active_border_color))
        assert_equal Theme::DARK.active_border_color, Testing.paint(f).cell(0, 0).style.fg

        Screen.instance.theme = Theme::DARK.with(active_border_color: Color::MAGENTA)
        assert_equal Color::MAGENTA, Testing.paint(f).cell(0, 0).style.fg
      end

      it "keeps a Theme::Ref unresolved" do
        ref = Theme.ref(:active_border_color)
        assert_equal ref, fill(color: ref).color
      end

      it "coerces a symbol" do
        assert_equal Color::GREEN, fill(color: :green).color
      end

      it "raises at assignment on a Ref the theme lacks" do
        assert_raises(KeyError) { fill.color = Theme.ref(:nope) }
      end
    end
  end
end
