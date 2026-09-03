# frozen_string_literal: true

module Tuile
  describe Component::HasCaption do
    before { Screen.fake }
    after { Screen.close }

    # A bare includer: the mixin's own behavior, without a component's painting.
    let(:captioned) do
      Class.new(Component) do
        include Component::HasCaption
      end
    end

    it "is empty when never set" do
      assert_equal StyledString::EMPTY, captioned.new.caption
      assert captioned.new.caption.empty?
    end

    it "parses a String, so embedded ANSI is honored" do
      c = captioned.new
      c.caption = "\e[31mred\e[0m"
      assert_equal "red", c.caption.to_s
      assert_equal Color::RED, c.caption.spans.first.style.fg
    end

    it "takes a StyledString as-is" do
      styled = StyledString.styled("Submit", fg: Color::RED)
      c = captioned.new
      c.caption = styled
      assert_equal styled, c.caption
    end

    it "clears on nil" do
      c = captioned.new
      c.caption = "Submit"
      c.caption = nil
      assert_equal StyledString::EMPTY, c.caption
    end

    it "invalidates on change" do
      c = captioned.new
      Screen.instance.content = c
      Screen.instance.invalidated_clear
      c.caption = "Submit"
      assert Screen.instance.invalidated?(c)
    end

    it "is a no-op when unchanged, including across the String/StyledString coercion" do
      c = captioned.new
      c.caption = "Submit"
      Screen.instance.content = c
      Screen.instance.invalidated_clear
      c.caption = "Submit"
      c.caption = StyledString.plain("Submit")
      assert !Screen.instance.invalidated?(c)
    end

    # The whole reason this is a mixin rather than per-class accessors: one
    # `is_a?(HasCaption)` plus a compare finds any captioned component, with no
    # hardcoded list of classes that happen to respond to `caption`.
    it "is the seam Testing.get looks a component up by" do
      window = Component::Window.new("Settings")
      button = Component::Button.new("Submit")
      window.content = button
      assert_same button, Testing.get(caption: "Submit", in: window)
      assert_same window, Testing.get(Component::Window, caption: /^Sett/, in: window)
    end
  end
end
