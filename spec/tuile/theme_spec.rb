# frozen_string_literal: true

module Tuile
  describe Theme do
    describe ".new" do
      it "accepts Color tokens" do
        t = Theme.new(active_bg_color: Color.palette(59), active_border_color: Color::GREEN,
                      input_bg_color: Color.rgb(10, 20, 30), hint_color: Color.palette(109))
        assert_equal Color.palette(59), t.active_bg_color
        assert_equal Color::GREEN, t.active_border_color
        assert_equal Color.rgb(10, 20, 30), t.input_bg_color
        assert_equal Color.palette(109), t.hint_color
      end

      it "defaults custom to an empty hash" do
        assert_equal({}, Theme::DARK.custom)
      end

      it "rejects a nil token" do
        e = assert_raises(TypeError) do
          Theme.new(active_bg_color: nil, active_border_color: Color::GREEN,
                    input_bg_color: Color.palette(238), hint_color: Color.palette(109))
        end
        assert_includes e.message, "active_bg_color"
      end

      it "rejects raw color forms — themes are strict, declaration sites spell out Color" do
        assert_raises(TypeError) do
          Theme.new(active_bg_color: 59, active_border_color: Color::GREEN,
                    input_bg_color: Color.palette(238), hint_color: Color.palette(109))
        end
        assert_raises(TypeError) do
          Theme.new(active_bg_color: Color.palette(59), active_border_color: :green,
                    input_bg_color: Color.palette(238), hint_color: Color.palette(109))
        end
      end

      it "rejects a non-Hash custom" do
        assert_raises(TypeError) { Theme::DARK.with(custom: [:accent]) }
      end

      it "rejects non-Symbol custom keys" do
        e = assert_raises(TypeError) { Theme::DARK.with(custom: { "accent" => Color::RED }) }
        assert_includes e.message, "accent"
      end

      it "rejects non-Color custom values" do
        e = assert_raises(TypeError) { Theme::DARK.with(custom: { accent: 208 }) }
        assert_includes e.message, ":accent"
      end

      it "freezes custom against later mutation" do
        tokens = { accent: Color.palette(208) }
        t = Theme::DARK.with(custom: tokens)
        assert t.custom.frozen?
        tokens[:error] = Color::RED # mutating the caller's hash must not leak in
        assert_equal [:accent], t.custom.keys
      end
    end

    describe "#with" do
      it "replaces a token while keeping the rest" do
        t = Theme::DARK.with(active_border_color: Color::CYAN)
        assert_equal Color::CYAN, t.active_border_color
        assert_equal Theme::DARK.active_bg_color, t.active_bg_color
      end

      it "validates replacement values too" do
        assert_raises(TypeError) { Theme::DARK.with(hint_color: nil) }
        assert_raises(TypeError) { Theme::DARK.with(hint_color: :cyan) }
      end

      it "preserves a Theme subclass" do
        subclass = Class.new(Theme)
        t = subclass.new(**Theme::DARK.to_h).with(active_border_color: Color::CYAN)
        assert_instance_of subclass, t
      end
    end

    describe "#[]" do
      it "looks up a custom token" do
        t = Theme::DARK.with(custom: { accent: Color.palette(208) })
        assert_equal Color.palette(208), t[:accent]
      end

      it "raises KeyError on an unknown token" do
        assert_raises(KeyError) { Theme::DARK[:accent] }
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

      it "fg wraps the text in a custom token's foreground color and a reset" do
        t = Theme::DARK.with(custom: { accent: Color.palette(208) })
        assert_equal "\e[38;5;208mNEW\e[0m", t.fg(:accent, "NEW")
      end

      it "bg wraps the text in a custom token's background color and a reset" do
        t = Theme::DARK.with(custom: { accent: Color.palette(208) })
        assert_equal "\e[48;5;208mNEW\e[0m", t.bg(:accent, "NEW")
      end

      it "fg/bg raise KeyError on an unknown token" do
        assert_raises(KeyError) { Theme::DARK.fg(:accent, "NEW") }
        assert_raises(KeyError) { Theme::DARK.bg(:accent, "NEW") }
      end
    end

    describe "DARK" do
      it "keeps the pre-theme colors" do
        assert_equal Color.palette(59), Theme::DARK.active_bg_color
        assert_equal Color::GREEN, Theme::DARK.active_border_color
        assert_equal Color.palette(238), Theme::DARK.input_bg_color
        assert_equal Color.palette(109), Theme::DARK.hint_color
      end
    end

    describe "LIGHT" do
      it "differs from DARK on the background tokens" do
        refute_equal Theme::DARK.active_bg_color, Theme::LIGHT.active_bg_color
        refute_equal Theme::DARK.input_bg_color, Theme::LIGHT.input_bg_color
        refute_equal Theme::DARK.hint_color, Theme::LIGHT.hint_color
      end
    end

    it "has structural equality, custom included" do
      copy = Theme.new(active_bg_color: Color.palette(59), active_border_color: Color::GREEN,
                       input_bg_color: Color.palette(238), hint_color: Color.palette(109))
      assert_equal Theme::DARK, copy
      refute_equal Theme::DARK, Theme::LIGHT
      refute_equal Theme::DARK, Theme::DARK.with(custom: { accent: Color::RED })
      assert_equal Theme::DARK.with(custom: { accent: Color::RED }),
                   Theme::DARK.with(custom: { accent: Color::RED })
    end
  end
end
