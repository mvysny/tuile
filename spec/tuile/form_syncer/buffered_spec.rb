# frozen_string_literal: true

module Tuile
  describe FormSyncer::Buffered do
    before { Screen.fake }
    after { Screen.close }

    # A model that counts its setter calls, to pin what the form syncer writes.
    let(:person_class) do
      Struct.new(:name, :age, :start_date, :end_date) do
        def writes = @writes ||= Hash.new(0)

        counting = Module.new do
          %i[name age start_date end_date].each do |m|
            define_method(:"#{m}=") do |v|
              writes[m] += 1
              super(v)
            end
          end
        end
        prepend counting
      end
    end

    let(:name) { Component::TextField.new }
    let(:age) { Component::IntegerField.new }
    let(:form) do
      Component::FormLayout.new.tap do |f|
        f.add(name, caption: "Name", required: true)
        f.add(age, caption: "Age")
      end
    end
    let(:person) { person_class.new("Alice", 30, 1, 9) }
    let(:syncer) do
      FormSyncer::Buffered.new.tap do |b|
        b.bind(name, :name).required("Name is required")
        b.bind(age, :age).validate { |v| "Must be positive" unless v.positive? }
      end
    end

    before { mount_at(form, Rect.new(0, 0, 40, 10)) }

    # @return [Hash{Symbol, nil => Array<String>}]
    def messages = syncer.last_validation.transform_values { |list| list.map(&:message) }

    it "is a FormSyncer, which can't be built on its own" do
      assert_kind_of FormSyncer, syncer
      assert_raises(Error) { FormSyncer.new }
    end

    context "bind" do
      it "refuses anything but a field" do
        assert_raises(ArgumentError) { syncer.bind(Component::Label.new, :x) }
      end

      it "refuses a second pipeline of the same attribute or field" do
        assert_raises(ArgumentError) { syncer.bind(Component::TextField.new, :name) }
        assert_raises(ArgumentError) { syncer.bind(name, :other) }
      end
    end

    context "read" do
      it "shows the model in the fields" do
        syncer.read(person)
        assert_equal ["Alice", 30], [name.value, age.value]
      end

      it "computes last_validation but shows no verdict" do
        syncer.read(person_class.new)
        assert_equal({ name: ["Name is required"] }, messages)
        assert_nil name.error_message
      end

      it "clears a verdict an earlier write? showed" do
        syncer.read(person_class.new)
        syncer.write?(person_class.new)
        syncer.read(person)
        assert_nil name.error_message
      end

      it "clears the fields for a nil model" do
        syncer.read(person)
        syncer.read(nil)
        assert_equal ["", nil], [name.value, age.value]
      end

      it "fires no setter, even over the \"\"-for-nil drift" do
        syncer.add_validator { nil }
        blank = person_class.new
        syncer.read(blank)
        assert_empty blank.writes
      end
    end

    context "an edit" do
      before { syncer.read(person_class.new) }

      it "shows that field's verdict and no other" do
        Testing.set_value(age, -1)
        assert_equal "Must be positive", age.error_message.to_s
        assert_nil name.error_message
      end

      it "clears the verdict once fixed" do
        Testing.set_value(age, -1)
        Testing.set_value(age, 5)
        assert_nil age.error_message
        refute syncer.last_validation.key?(:age)
      end

      it "writes nothing to the model" do
        blank = person_class.new
        syncer.read(blank)
        Testing.set_value(name, "Bob")
        assert_nil blank.name
      end

      it "reaches the FormItem's message row" do
        Testing.set_value(age, -1)
        Screen.instance.repaint
        assert_includes Screen.instance.buffer.text.join("\n"), "Must be positive"
      end

      it "is not an app's programmatic write" do
        age.value = -1
        assert_nil age.error_message
        refute syncer.changed?
      end
    end

    context "bad input" do
      before do
        syncer.read(person)
        age.clear
        Screen.instance.focused = age
        Screen.instance.send(:handle_key?, "-")
      end

      it "lands in last_validation with the field's own report, though no value moved" do
        assert_equal({ age: [age.bad_input_message] }, messages)
      end

      it "writes no verdict — the field shows its own report" do
        assert_nil age.error_message
      end

      it "blocks the write even on an optional field" do
        refute syncer.write?(person)
        assert_equal 30, person.age
      end
    end

    context "write?" do
      before { syncer.read(person) }

      it "writes the fields and answers true" do
        Testing.set_value(name, "Bob")
        assert syncer.write?(person)
        assert_equal "Bob", person.name
      end

      it "writes only what differs" do
        Testing.set_value(name, "Bob")
        syncer.write?(person)
        assert_equal({ name: 1 }, person.writes)
      end

      it "leaves the model alone and shows every verdict on a failure" do
        Testing.set_value(name, "")
        refute syncer.write?(person)
        assert_equal "Alice", person.name
        assert_equal "Name is required", name.error_message.to_s
      end

      it "may write into another model than read's" do
        other = person_class.new
        assert syncer.write?(other)
        assert_equal ["Alice", 30], [other.name, other.age]
      end

      it "refuses a nil model" do
        assert_raises(ArgumentError) { syncer.write?(nil) }
      end
    end

    context "write!" do
      it "raises ValidationError carrying the map" do
        syncer.read(person_class.new)
        e = assert_raises(FormSyncer::ValidationError) { syncer.write!(person_class.new) }
        assert_equal syncer.last_validation, e.failures
        assert_kind_of Error, e
      end
    end

    context "model validators" do
      before do
        syncer.add_validator { |p| "Too old for this form" if p.age > 100 }
        syncer.add_validator { |p| { name: "Reserved" } if p.name == "root" }
        syncer.read(person)
      end

      it "puts a form-level failure under the nil key" do
        Testing.set_value(age, 200)
        refute syncer.write?(person)
        assert_equal({ nil => ["Too old for this form"] }, messages)
      end

      it "lands a blame on the blamed field" do
        Testing.set_value(name, "root")
        refute syncer.write?(person)
        assert_equal "Reserved", name.error_message.to_s
      end

      it "sees the candidates in the model, then reverts them" do
        Testing.set_value(age, 200)
        syncer.write?(person)
        assert_equal 30, person.age
        assert_equal 2, person.writes[:age], "written, then restored"
      end

      it "doesn't run while a field fails" do
        Testing.set_value(age, 200)
        Testing.set_value(name, "")
        refute syncer.write?(person)
        refute syncer.last_validation.key?(nil)
      end

      it "keeps its message after the fixing edit, until the next write?" do
        Testing.set_value(name, "root")
        syncer.write?(person)
        Testing.set_value(name, "Bob")
        assert_equal "Reserved", name.error_message.to_s
        assert syncer.write?(person)
        assert_nil name.error_message
      end

      it "raises on a model validator answering false" do
        syncer.add_validator { false }
        assert_raises(Error) { syncer.write?(person) }
      end
    end

    context "validate" do
      before do
        syncer.add_validator { |p| "Too old for this form" if p.age > 100 }
        syncer.read(person)
      end

      it "runs the model validators against read's model and leaves it as it was" do
        Testing.set_value(age, 200)
        assert_equal({ nil => ["Too old for this form"] }, syncer.validate.transform_values { _1.map(&:message) })
        assert_equal 30, person.age
      end

      it "shows every verdict" do
        Testing.set_value(name, "")
        syncer.read(person_class.new(nil, -1))
        syncer.validate
        assert_equal ["Name is required", "Must be positive"], [name.error_message.to_s, age.error_message.to_s]
      end
    end

    context "changed?" do
      before { syncer.read(person) }

      it "turns on with a user's edit" do
        refute syncer.changed?
        Testing.set_value(name, "Bob")
        assert syncer.changed?
      end

      it "counts an edit reverted by hand — edited, not differing" do
        Testing.set_value(name, "Bob")
        Testing.set_value(name, "Alice")
        assert syncer.changed?
      end

      it "resets on a successful write? and on read" do
        Testing.set_value(name, "Bob")
        syncer.write?(person)
        refute syncer.changed?
        Testing.set_value(name, "Carol")
        syncer.read(person)
        refute syncer.changed?
      end
    end
  end
end
