# frozen_string_literal: true

module Tuile
  describe ThemeDef do
    let(:custom_dark) { Theme::DARK.with(custom: { accent: Color.palette(208) }) }
    let(:custom_light) { Theme::LIGHT.with(custom: { accent: Color.palette(130) }) }

    describe ".new" do
      it "holds the dark/light pair" do
        d = ThemeDef.new(dark: custom_dark, light: custom_light)
        assert_equal custom_dark, d.dark
        assert_equal custom_light, d.light
      end

      it "rejects a non-Theme member" do
        e = assert_raises(TypeError) { ThemeDef.new(dark: :dark, light: Theme::LIGHT) }
        assert_includes e.message, "dark"
        e = assert_raises(TypeError) { ThemeDef.new(dark: Theme::DARK, light: nil) }
        assert_includes e.message, "light"
      end

      it "rejects mismatched custom token sets — the missing token would " \
         "otherwise KeyError only when the user flips the OS appearance" do
        e = assert_raises(ArgumentError) { ThemeDef.new(dark: custom_dark, light: Theme::LIGHT) }
        assert_includes e.message, ":accent"
      end

      it "accepts the same custom token set regardless of declaration order" do
        dark = Theme::DARK.with(custom: { accent: Color::RED, error: Color::RED })
        light = Theme::LIGHT.with(custom: { error: Color::RED, accent: Color::RED })
        ThemeDef.new(dark:, light:) # must not raise
      end
    end

    describe "#for" do
      let(:def_) { ThemeDef.new(dark: custom_dark, light: custom_light) }

      it "picks light for :light" do
        assert_equal custom_light, def_.for(:light)
      end

      it "picks dark for :dark" do
        assert_equal custom_dark, def_.for(:dark)
      end

      it "picks dark for anything else, matching the inconclusive-means-dark policy" do
        assert_equal custom_dark, def_.for(nil)
      end
    end

    describe "DEFAULT" do
      it "pairs the built-in themes" do
        assert_equal Theme::DARK, ThemeDef::DEFAULT.dark
        assert_equal Theme::LIGHT, ThemeDef::DEFAULT.light
      end
    end

    it "has structural equality" do
      assert_equal ThemeDef.new(dark: Theme::DARK, light: Theme::LIGHT), ThemeDef::DEFAULT
      refute_equal ThemeDef.new(dark: custom_dark, light: custom_light), ThemeDef::DEFAULT
    end
  end
end
