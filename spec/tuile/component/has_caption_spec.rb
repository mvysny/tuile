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

    # Deliberately *not* a lookup seam: Testing has no `caption:` term, because
    # a component's mixin membership must not be answerable by what a test
    # locator finds convenient (`D_component_lookup`). What the mixin is for is
    # the shared value rule below — one coercion, one short-circuit, one
    # invalidate — so four includers cannot drift on them.
    it "is a marker naming the shape, not a handle Testing looks up by" do
      window = Component::Window.new("Settings")
      button = Component::Button.new("Submit")
      window.content = button
      assert_kind_of Component::HasCaption, button
      assert_kind_of Component::HasCaption, window
      assert_same button, Testing.get(Component::Button, in: window)
    end
  end
end
