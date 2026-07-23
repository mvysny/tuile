# frozen_string_literal: true

module Tuile
  describe Component::HasValue do
    before { Screen.fake }
    after { Screen.close }

    # A bare component leaning on the mixin's default @value storage — stands
    # in for the combo box that will consume it for real.
    def default_holder
      Class.new(Component) { include Component::HasValue }.new
    end

    it "value defaults to nil and reports empty" do
      c = default_holder
      assert_nil c.value
      assert c.empty?
    end

    it "value= stores an arbitrary-typed value" do
      c = default_holder
      obj = Object.new
      c.value = obj
      assert_same obj, c.value
      refute c.empty?
    end

    it "value= fires on_value_change with the new value, but not on a no-op set" do
      c = default_holder
      seen = []
      c.on_value_change = ->(v) { seen << v }
      c.value = 1
      c.value = 1
      c.value = 2
      assert_equal [1, 2], seen
    end

    it "clear resets to empty_value and fires the listener" do
      c = default_holder
      c.value = 7
      seen = []
      c.on_value_change = ->(v) { seen << v }
      c.clear
      assert_nil c.value
      assert c.empty?
      assert_equal [nil], seen
    end

    it "honors an overridden empty_value" do
      c = Class.new(Component) do
        include Component::HasValue
        def empty_value = 0
      end.new
      c.value = 0
      assert c.empty?
      c.value = 5
      refute c.empty?
    end

    describe "AbstractStringField as a HasValue" do
      def field(text: "")
        f = Component::TextField.new
        f.rect = Rect.new(0, 0, 20, 1)
        f.text = text
        f
      end

      it "value mirrors text both ways" do
        f = field(text: "hi")
        assert_equal "hi", f.value
        f.value = "bye"
        assert_equal "bye", f.text
      end

      it "empty? tracks the blank buffer via empty_value \"\"" do
        f = field
        assert f.empty?
        f.text = "x"
        refute f.empty?
      end

      it "text= fires on_value_change alongside on_change" do
        f = field
        changed = []
        valued = []
        f.on_change = ->(t) { changed << t }
        f.on_value_change = ->(v) { valued << v }
        f.text = "abc"
        assert_equal ["abc"], changed
        assert_equal ["abc"], valued
      end

      it "clear empties the field and fires both listeners" do
        f = field(text: "abc")
        changed = []
        valued = []
        f.on_change = ->(t) { changed << t }
        f.on_value_change = ->(v) { valued << v }
        f.clear
        assert_equal "", f.text
        assert_equal [""], changed
        assert_equal [""], valued
      end
    end
  end
end
