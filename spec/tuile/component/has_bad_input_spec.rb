# frozen_string_literal: true

module Tuile
  describe Component::HasBadInput do
    before { Screen.fake }
    after { Screen.close }

    # A bare component including the mixin without overriding the one member.
    def forgetful = Class.new(Component) { include Component::HasBadInput }.new

    # The shape every includer has: a message iff the input is there and won't
    # convert.
    def reporter(message)
      Class.new(Component) do
        include Component::HasBadInput
        attr_accessor :input

        define_method(:bad_input_message) { input.to_s.empty? ? nil : message }
      end.new
    end

    it "bad_input_message raises unless the includer overrides it" do
      e = assert_raises(NotImplementedError) { forgetful.bad_input_message }
      assert_match(/must implement bad_input_message/, e.message)
    end

    it "bad_input? raises through the missing override too" do
      assert_raises(NotImplementedError) { forgetful.bad_input? }
    end

    it "bad_input? is the message's presence" do
      c = reporter("nope")
      refute c.bad_input?
      c.input = "xyz"
      assert c.bad_input?
      assert_equal "nope", c.bad_input_message
    end

    it "is a locator seam: a consumer finds includers without a class list" do
      fields = [Component::TextField.new, Component::IntegerField.new, Component::Checkbox.new]
      assert_equal [Component::IntegerField], fields.grep(Component::HasBadInput).map(&:class)
      # And the Ruby-native form of the same question, for a mixed bag.
      answerers = fields.select { _1.respond_to?(:bad_input?) }
      assert_equal 1, answerers.size
    end

    it "is not on HasValue: a field-kind concept stays off every other input" do
      refute Component::HasValue.include?(Component::HasBadInput)
      [Component::TextField, Component::TextArea, Component::PasswordField, Component::Checkbox,
       Component::CheckboxGroup, Component::RadioGroup, Component::Select, Component::ComboBox].each do |klass|
        refute klass.include?(Component::HasBadInput), "#{klass} should not report bad input"
        refute klass.new.respond_to?(:bad_input?), "#{klass} should not report bad input"
      end
    end
  end
end
