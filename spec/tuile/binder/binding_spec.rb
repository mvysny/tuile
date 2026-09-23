# frozen_string_literal: true

module Tuile
  describe Binder::Binding do
    before { Screen.fake }
    after { Screen.close }

    let(:text) { Component::TextField.new }
    let(:number) { Component::IntegerField.new }
    let(:model) { Struct.new(:name, :age, :iso).new }

    # @return [String, nil] the failure's message, `nil` on a pass.
    def verdict_of(binding) = binding.run.failure&.message

    context "the chain" do
      it "passes the field's value through as the candidate" do
        text.value = "Bob"
        assert_equal "Bob", Binder::Binding.new(text, :name).run.candidate
      end

      it "fails with the first validator's message" do
        text.value = "Bo"
        binding = Binder::Binding.new(text, :name)
                                 .validate { |v| "too short" if v.length < 3 }
                                 .validate { "never reached" }
        assert_equal "too short", verdict_of(binding)
        assert_equal "Bo", binding.run.failure.value
      end

      it "skips validators for nil" do
        binding = Binder::Binding.new(number, :age).validate { |v| "must be positive" unless v.positive? }
        assert_nil verdict_of(binding)
      end

      it "hands a TextField's validators \"\", not nil" do
        seen = :none
        Binder::Binding.new(text, :name).validate { |v| seen = v and nil }.run
        assert_equal "", seen
      end

      it "raises on a validator answering true or false, the predicate mistake" do
        number.value = 5
        assert_raises(Error) { Binder::Binding.new(number, :age).validate(&:positive?).run }
        number.value = -5
        assert_raises(Error) { Binder::Binding.new(number, :age).validate(&:positive?).run }
      end

      it "asks required before the chain, wherever it was written" do
        binding = Binder::Binding.new(text, :name).validate { "chain" }.required("Name is required")
        assert_equal "Name is required", verdict_of(binding)
        text.value = "Bob"
        assert_equal "chain", verdict_of(binding)
      end
    end

    context "bad input" do
      before do
        mount_at(number, Rect.new(0, 0, 10, 1))
        Screen.instance.focused = number
        Screen.instance.send(:handle_key?, "-")
      end

      it "fails first, with the field's own report, flagged as bad input" do
        outcome = Binder::Binding.new(number, :age).required("Age is required").run
        assert_equal number.bad_input_message, outcome.failure.message
        assert outcome.bad_input
      end

      it "fails an optional field too" do
        refute Binder::Binding.new(number, :age).run.ok?
      end
    end

    context "converters" do
      let(:iso) do
        Binder::Binding.new(text, :iso).convert(->(s) { Date.iso8601(s) }, :iso8601.to_proc)
      end

      it "converts the value to the model form" do
        text.value = "2026-09-23"
        assert_equal Date.new(2026, 9, 23), iso.run.candidate
      end

      it "turns an ArgumentError into the verdict" do
        text.value = "nope"
        assert_equal "invalid date", verdict_of(iso)
      end

      it "lets error: override the message" do
        text.value = "nope"
        binding = Binder::Binding.new(text, :iso).convert(->(s) { Date.iso8601(s) }, :to_s.to_proc, error: "Not a date")
        assert_equal "Not a date", verdict_of(binding)
      end

      it "maps the field's empty value to nil without calling the converter" do
        assert_nil iso.run.candidate
        assert iso.run.ok?
      end

      it "rescues nothing but ArgumentError" do
        text.value = "x"
        binding = Binder::Binding.new(text, :iso).convert(->(_) { raise TypeError }, :to_s.to_proc)
        assert_raises(TypeError) { binding.run }
      end

      it "hands a validator after it the model form" do
        text.value = "2026-09-23"
        seen = nil
        iso.validate { |d| seen = d and nil }.run
        assert_equal Date.new(2026, 9, 23), seen
      end
    end

    context "populate" do
      it "shows the attribute through every converter, backwards" do
        model.iso = Date.new(2026, 9, 23)
        Binder::Binding.new(text, :iso).convert(->(s) { Date.iso8601(s) }, :iso8601.to_proc).populate(model)
        assert_equal "2026-09-23", text.value
      end

      it "shows nil as the field's empty value" do
        text.value = "stale"
        Binder::Binding.new(text, :name).populate(model)
        assert_equal "", text.value
      end

      it "clears bad input, which a nil value= would leave on screen" do
        mount_at(number, Rect.new(0, 0, 10, 1))
        Screen.instance.focused = number
        Screen.instance.send(:handle_key?, "-")
        Binder::Binding.new(number, :age).populate(model)
        refute number.bad_input?
      end

      it "propagates a to_value failure: a malformed stored value is the app's data" do
        model.iso = "garbage"
        binding = Binder::Binding.new(text, :iso).convert(:to_s.to_proc, ->(s) { Date.iso8601(s).to_s })
        assert_raises(Date::Error) { binding.populate(model) }
      end
    end
  end
end
