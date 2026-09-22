# frozen_string_literal: true

module Tuile
  describe Component::HasBadInput do
    before { Screen.fake }
    after { Screen.close }

    # A bare component including the mixin without overriding the one member.
    def forgetful = Class.new(Component) { include Component::HasBadInput }.new

    # The shape every includer has: a message iff the input is there and won't
    # convert, plus the latch, down by default as the mixin's is.
    def reporter(message)
      Class.new(Component) do
        include Component::HasBadInput
        attr_accessor :input
        attr_writer :settled

        define_method(:bad_input_message) { input.to_s.empty? ? nil : message }
        def bad_input_settled? = @settled.nil? || @settled
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

    describe "on_bad_input_change" do
      # Each includer calls the sole writer from its own sites; those call lists
      # are specced in the fields' own specs, the shape here.
      def sync(component) = component.send(:sync_bad_input)

      def field_with_editor
        f = Component::IntegerField.new
        Screen.instance.content = f
        f
      end

      def editor(fld) = Testing.get(Component::TextField, in: fld)

      it "fires on the edge of the report, not once per input" do
        c = reporter("nope")
        seen = []
        c.on_bad_input_change { |e| seen << e.message }
        c.input = "x"
        sync(c)
        c.input = "xy" # still bad, still the same report
        sync(c)
        assert_equal ["nope"], seen
      end

      it "fires nil when the input converts again" do
        c = reporter("nope")
        c.input = "x"
        sync(c)
        seen = []
        c.on_bad_input_change { |e| seen << e.message }
        c.input = ""
        sync(c)
        assert_equal [nil], seen
      end

      it "carries the field as the event's source" do
        c = reporter("nope")
        seen = []
        c.on_bad_input_change { |e| seen << e }
        c.input = "x"
        sync(c)
        assert_same c, seen.first.source
        assert_kind_of Tuile::Event, seen.first
        assert seen.first.frozen?
      end

      it "stays silent while the latch holds, and fires the moment it settles" do
        c = reporter("nope")
        c.settled = false
        seen = []
        c.on_bad_input_change { |e| seen << e.message }
        c.input = "x"
        sync(c)
        assert_empty seen, "a latched field must not announce a report it is not showing"
        c.settled = true
        sync(c)
        assert_equal ["nope"], seen
      end

      it "leaves the pull alone: bad_input? never waits for the latch" do
        c = reporter("nope")
        c.settled = false
        c.input = "x"
        assert c.bad_input?
        assert_equal "nope", c.bad_input_message
      end

      it "wires an AbstractWrappingField includer through its edit funnel" do
        f = field_with_editor
        seen = []
        f.on_bad_input_change { |e| seen << e.message }
        editor(f).value = "-" # the one buffer an integer field's filter must admit
        editor(f).value = "-5"
        assert_equal ["not a whole number", nil], seen
      end
    end

    describe "shown_message" do
      it "prefers the field's own report over a verdict" do
        c = reporter("nope")
        c.error_message = "must be in the past"
        c.input = "x"
        assert_equal "nope", c.shown_message
      end

      it "falls back to the verdict while the report is latched" do
        c = reporter("nope")
        c.settled = false
        c.error_message = "must be in the past"
        c.input = "x"
        assert_equal "must be in the past", c.shown_message.to_s
      end

      it "is the verdict, then nothing, when the input converts" do
        c = reporter("nope")
        c.error_message = "must be in the past"
        assert_equal "must be in the past", c.shown_message.to_s
        c.error_message = nil
        assert_nil c.shown_message
      end
    end

    describe "wears_bad_input_ink?" do
      it "hands the well to a child without swallowing a verdict" do
        c = reporter("nope")
        c.define_singleton_method(:wears_bad_input_ink?) { false }
        c.input = "x"
        refute c.send(:error_ink?), "the child wearing the fault means this one does not"
        c.error_message = "must be in the past"
        assert c.send(:error_ink?), "a verdict is nobody else's to wear"
      end
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
