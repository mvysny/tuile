# frozen_string_literal: true

module Tuile
  describe Component::HasPlaceholder do
    before { Screen.fake }
    after { Screen.close }

    # A bare includer: the mixin's own behavior, without a component's painting.
    let(:hinted) do
      Class.new(Component) do
        include Component::HasPlaceholder
      end
    end

    it "is nil when never set" do
      assert_nil hinted.new.placeholder
    end

    it "round-trips a String and clears on nil" do
      c = hinted.new
      c.placeholder = "dd.mm.yyyy"
      assert_equal "dd.mm.yyyy", c.placeholder
      c.placeholder = nil
      assert_nil c.placeholder
    end

    # The ink is the theme's, deliberately calibrated — so a StyledString is
    # refused rather than flattened to its text, which would silently drop the
    # colors the caller asked for.
    it "refuses a StyledString rather than flattening it" do
      c = hinted.new
      assert_raises(TypeError) { c.placeholder = StyledString.plain("dd.mm.yyyy") }
      assert_raises(TypeError) { c.placeholder = 42 }
      assert_nil c.placeholder
    end

    it "invalidates on change, and is a no-op when unchanged" do
      c = hinted.new
      Screen.instance.content = c
      Screen.instance.invalidated_clear
      c.placeholder = "hint"
      assert Screen.instance.invalidated?(c)

      Screen.instance.invalidated_clear
      c.placeholder = "hint"
      assert !Screen.instance.invalidated?(c)
    end

    it "shows in Component#inspect only once set" do
      c = hinted.new
      assert !c.inspect.include?("placeholder")
      c.placeholder = "dd.mm.yyyy"
      assert c.inspect.include?('placeholder="dd.mm.yyyy"')
    end

    # The reason it is a mixin rather than a per-class accessor: one `is_a?`
    # finds every field that can carry a hint, whatever its class.
    it "is the seam a tree walk finds a hintable field by" do
      layout = Component::Layout::Absolute.new
      field = Component::TextField.new
      integer = Component::IntegerField.new
      layout.add(field)
      layout.add(integer)
      layout.add(Component::Label.new("not a field"))

      found = Testing.find(Component::HasPlaceholder, in: layout)
      assert_includes found, field
      assert_includes found, integer
      # Three, not two: a composed field's inner face is a TextField, so it
      # carries the mixin as well. The composer's accessors *delegate* to that
      # face rather than shadowing it, so both report the same hint.
      assert_includes found, Testing.get(Component::TextField, in: integer)
      assert_equal 3, found.size

      integer.placeholder = "0-65535"
      assert_equal "0-65535", Testing.get(Component::TextField, in: integer).placeholder
    end
  end
end
