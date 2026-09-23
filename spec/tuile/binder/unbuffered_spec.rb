# frozen_string_literal: true

module Tuile
  describe Binder::Unbuffered do
    before { Screen.fake }
    after { Screen.close }

    let(:model_class) { Struct.new(:name, :start_day, :end_day) }
    let(:name) { Component::TextField.new }
    let(:start_day) { Component::IntegerField.new }
    let(:end_day) { Component::IntegerField.new }
    let(:form) do
      Component::FormLayout.new.tap do |f|
        f.add(name, caption: "Name")
        f.add(start_day, caption: "Start")
        f.add(end_day, caption: "End")
      end
    end
    let(:plan) { model_class.new("Trip", 1, 5) }
    let(:binder) do
      Binder::Unbuffered.new.tap do |b|
        b.bind(name, :name).required("Name is required")
        b.bind(start_day, :start_day).required("Pick a start")
        b.bind(end_day, :end_day).required("Pick an end")
        b.rule { |p| { end_day: "Ends before it starts" } if p.end_day < p.start_day }
      end
    end

    before { mount_at(form, Rect.new(0, 0, 40, 12)) }

    # @return [Hash{Symbol, nil => Array<String>}]
    def messages = binder.last_validation.transform_values { |list| list.map(&:message) }

    context "model=" do
      it "shows the model and writes nothing, even over the \"\"-for-nil drift" do
        blank = model_class.new(nil, 1, 5)
        binder.model = blank
        assert_equal "", name.value
        assert_nil blank.name
      end

      it "computes last_validation but shows no verdict" do
        binder.model = model_class.new(nil, 1, 5)
        assert_equal({ name: ["Name is required"] }, messages)
        assert_nil name.error_message
      end
    end

    context "an edit" do
      before { binder.model = plan }

      it "writes a valid value through at once" do
        Testing.set_value(name, "Holiday")
        assert_equal "Holiday", plan.name
      end

      it "keeps an invalid one out, and shows why" do
        Testing.set_value(name, "")
        assert_equal "Trip", plan.name
        assert_equal "Name is required", name.error_message.to_s
      end

      it "runs the rules, reverting the write and blaming the field" do
        Testing.set_value(start_day, 9)
        assert_equal 1, plan.start_day
        assert_equal({ end_day: ["Ends before it starts"] }, messages)
        assert_equal "Ends before it starts", end_day.error_message.to_s
      end

      it "writes every field changed since model= once a later edit makes them pass" do
        Testing.set_value(start_day, 9)
        Testing.set_value(end_day, 20)
        assert_equal [9, 20], [plan.start_day, plan.end_day]
        assert_empty binder.last_validation
        assert_nil end_day.error_message
      end

      it "holds every changed field back while one of them fails" do
        Testing.set_value(name, "")
        Testing.set_value(end_day, 7)
        assert_equal 5, plan.end_day
      end

      it "is not an app's programmatic write" do
        name.value = "Programmatic"
        assert_equal "Trip", plan.name
      end
    end

    context "no model" do
      it "validates edits and writes nothing" do
        binder.model = nil
        Testing.set_value(name, "x")
        Testing.set_value(name, "")
        assert_equal "Name is required", name.error_message.to_s
      end
    end

    context "validate" do
      it "shows every verdict and writes nothing" do
        binder.model = model_class.new(nil, 1, 5)
        assert_equal({ name: ["Name is required"] }, binder.validate.transform_values { _1.map(&:message) })
        assert_equal "Name is required", name.error_message.to_s
      end
    end
  end
end
