# frozen_string_literal: true

module Tuile
  describe Theme do
    describe ".new" do
      it "coerces raw color forms to Color" do
        t = Theme.new(active_bg_color: 59, active_border_color: :green,
                      input_bg_color: [10, 20, 30], hint_color: Color.new(109))
        assert_equal Color.new(59), t.active_bg_color
        assert_equal Color::GREEN, t.active_border_color
        assert_equal Color.new([10, 20, 30]), t.input_bg_color
        assert_equal Color.new(109), t.hint_color
      end

      it "rejects a nil token" do
        e = assert_raises(ArgumentError) do
          Theme.new(active_bg_color: nil, active_border_color: :green, input_bg_color: 238, hint_color: 109)
        end
        assert_includes e.message, "active_bg_color"
      end

      it "rejects an invalid color form" do
        assert_raises(ArgumentError) do
          Theme.new(active_bg_color: :neon, active_border_color: :green, input_bg_color: 238, hint_color: 109)
        end
      end
    end

    describe "#with" do
      it "coerces replacement values too" do
        t = Theme::DARK.with(active_border_color: :cyan)
        assert_equal Color::CYAN, t.active_border_color
        assert_equal Theme::DARK.active_bg_color, t.active_bg_color
      end

      it "rejects nil replacement values" do
        assert_raises(ArgumentError) { Theme::DARK.with(hint_color: nil) }
      end
    end

    describe "rendering helpers" do
      it "active_bg wraps the text in the background color and a reset" do
        assert_equal "\e[48;5;59m[ Ok ]\e[0m", Theme::DARK.active_bg("[ Ok ]")
      end

      it "active_border wraps the text in the foreground color and a reset" do
        assert_equal "\e[32m┌─┐\e[0m", Theme::DARK.active_border("┌─┐")
      end

      it "active_border passes embedded escapes through verbatim" do
        frame = "\e[2;3H│"
        assert_equal "\e[32m#{frame}\e[0m", Theme::DARK.active_border(frame)
      end

      it "input_bg wraps the text in the background color and a reset" do
        assert_equal "\e[48;5;238mhi \e[0m", Theme::DARK.input_bg("hi ")
      end

      it "hint wraps the text in the foreground color and a reset" do
        assert_equal "\e[38;5;109mquit\e[0m", Theme::DARK.hint("quit")
      end
    end

    describe "DARK" do
      it "keeps the pre-theme colors" do
        assert_equal Color.new(59), Theme::DARK.active_bg_color
        assert_equal Color::GREEN, Theme::DARK.active_border_color
        assert_equal Color.new(238), Theme::DARK.input_bg_color
        assert_equal Color.new(109), Theme::DARK.hint_color
      end
    end

    describe "LIGHT" do
      it "differs from DARK on the background tokens" do
        refute_equal Theme::DARK.active_bg_color, Theme::LIGHT.active_bg_color
        refute_equal Theme::DARK.input_bg_color, Theme::LIGHT.input_bg_color
        refute_equal Theme::DARK.hint_color, Theme::LIGHT.hint_color
      end
    end

    it "has structural equality" do
      copy = Theme.new(active_bg_color: 59, active_border_color: :green, input_bg_color: 238, hint_color: 109)
      assert_equal Theme::DARK, copy
      refute_equal Theme::DARK, Theme::LIGHT
    end
  end
end
