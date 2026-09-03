# frozen_string_literal: true

module Tuile
  describe Theme do
    # Every token spelled out once, so an example overrides only the one it is
    # about. The values are DARK's, which is what the equality example needs.
    def theme_args(**overrides)
      { active_bg_color: Color.palette(59), active_border_color: Color::GREEN,
        input_bg_color: Color.palette(238), hint_color: Color.palette(109),
        error_color: Color.palette(203), error_bg_color: Color.palette(88),
        error_active_bg_color: Color.palette(95), scrollbar_color: Color.palette(59) }.merge(overrides)
    end

    describe ".new" do
      it "accepts Color tokens" do
        t = Theme.new(**theme_args(input_bg_color: Color.rgb(10, 20, 30)))
        assert_equal Color.palette(59), t.active_bg_color
        assert_equal Color::GREEN, t.active_border_color
        assert_equal Color.rgb(10, 20, 30), t.input_bg_color
        assert_equal Color.palette(109), t.hint_color
        assert_equal Color.palette(59), t.scrollbar_color
      end

      it "defaults custom to an empty hash" do
        assert_equal({}, Theme::DARK.custom)
      end

      it "rejects a nil token" do
        e = assert_raises(TypeError) do
          Theme.new(**theme_args(active_bg_color: nil))
        end
        assert_includes e.message, "active_bg_color"
      end

      it "rejects raw color forms — themes are strict, declaration sites spell out Color" do
        assert_raises(TypeError) do
          Theme.new(**theme_args(active_bg_color: 59))
        end
        assert_raises(TypeError) do
          Theme.new(**theme_args(active_border_color: :green))
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

    describe ".ref / Ref" do
      it "builds a Ref naming a token" do
        assert_equal Theme::Ref.new(:accent), Theme.ref(:accent)
      end

      it "resolves against a theme's custom token" do
        t = Theme::DARK.with(custom: { accent: Color.palette(208) })
        assert_equal Color.palette(208), Theme.ref(:accent).resolve(t)
      end

      it "resolves a built-in chrome token" do
        assert_equal Theme::DARK.input_bg_color, Theme.ref(:input_bg_color).resolve(Theme::DARK)
        assert_equal Theme::LIGHT.input_bg_color, Theme.ref(:input_bg_color).resolve(Theme::LIGHT)
      end

      it "tracks a chrome token across themes (the live-ref point)" do
        ref = Theme.ref(:active_bg_color)
        refute_equal ref.resolve(Theme::DARK), ref.resolve(Theme::LIGHT)
      end

      it "chrome_token? distinguishes built-in names from custom ones" do
        assert Theme.chrome_token?(:input_bg_color)
        assert Theme.chrome_token?(:scrollbar_color)
        refute Theme.chrome_token?(:accent)
        refute Theme.chrome_token?(:custom)
      end

      it "a chrome name wins over a same-named custom token" do
        t = Theme::DARK.with(custom: { input_bg_color: Color.palette(9) })
        assert_equal Theme::DARK.input_bg_color, Theme.ref(:input_bg_color).resolve(t)
      end

      it "resolve raises KeyError for a name that is neither chrome nor custom" do
        assert_raises(KeyError) { Theme.ref(:accent).resolve(Theme::DARK) }
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

      it "gives the scrollbar the weight of the selection well" do
        assert_equal Theme::DARK.active_bg_color, Theme::DARK.scrollbar_color
      end
    end

    describe "LIGHT" do
      it "differs from DARK on the background tokens" do
        refute_equal Theme::DARK.active_bg_color, Theme::LIGHT.active_bg_color
        refute_equal Theme::DARK.input_bg_color, Theme::LIGHT.input_bg_color
        refute_equal Theme::DARK.hint_color, Theme::LIGHT.hint_color
        refute_equal Theme::DARK.error_color, Theme::LIGHT.error_color
        refute_equal Theme::DARK.scrollbar_color, Theme::LIGHT.scrollbar_color
      end
    end

    # The three conditions `D_has_validation` measured every candidate well
    # against, kept as a guard rather than a script to re-run by hand. C is the
    # one that kills candidates: lose it and a focused invalid Select shows no
    # focus at all, since it paints no caret. `ansi16` is deliberately not
    # asserted — B is unreachable there for both pairs, and focus is already
    # invisible at that depth (GREY27 and GREY37 both quantize to
    # :bright_black), so the entry accepts it.
    describe "the error wells" do
      %i[truecolor palette256].each do |depth|
        { "DARK" => Theme::DARK, "LIGHT" => Theme::LIGHT }.each do |name, theme|
          it "stay distinguishable in #{name} at #{depth}" do
            resting = theme.error_bg_color.quantize(depth)
            focused = theme.error_active_bg_color.quantize(depth)

            refute_equal theme.input_bg_color.quantize(depth), resting # A
            refute_equal theme.active_bg_color.quantize(depth), focused # B
            refute_equal resting, focused # C
          end
        end
      end
    end

    it "has structural equality, custom included" do
      copy = Theme.new(**theme_args)
      assert_equal Theme::DARK, copy
      refute_equal Theme::DARK, Theme::LIGHT
      refute_equal Theme::DARK, Theme::DARK.with(custom: { accent: Color::RED })
      assert_equal Theme::DARK.with(custom: { accent: Color::RED }),
                   Theme::DARK.with(custom: { accent: Color::RED })
    end
  end
end
