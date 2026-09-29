# frozen_string_literal: true

module Tuile
  describe Component::HasValueChangeMode do
    before { Screen.fake }
    after { Screen.close }

    let(:screen) { Screen.instance }
    let(:queue) { screen.event_queue }

    def mounted(field)
      mount_at(field, Rect.new(0, 0, 20, 1))
      field
    end

    def focused(field)
      mounted(field)
      screen.focused = field
      field
    end

    def type(text) = text.each_char { |c| screen.send(:handle_key?, c) }

    def notices(field)
      seen = []
      field.on_value_change { |e| seen << [e.value, e.from_user?] }
      seen
    end

    describe "the knob" do
      it "defaults to :commit, and to Vaadin's 400 ms wait" do
        f = Component::TextField.new
        assert_equal :commit, f.value_change_mode
        assert_in_delta 0.4, f.value_change_timeout
      end

      it "rejects an unknown mode and a negative timeout" do
        f = Component::TextField.new
        assert_raises(ArgumentError) { f.value_change_mode = :on_change }
        assert_raises(ArgumentError) { f.value_change_timeout = -1 }
        assert_raises(ArgumentError) { f.value_change_timeout = "1" }
      end

      it "reaches the string and number fields, and not the date fields" do
        [Component::TextField, Component::PasswordField, Component::TextArea,
         Component::IntegerField, Component::FloatField, Component::BigDecimalField].each do |c|
          assert_includes c.ancestors, Component::HasValueChangeMode
        end
        [Component::DateField, Component::TimeField, Component::DateTimeField, Component::ComboBox].each do |c|
          refute_includes c.ancestors, Component::HasValueChangeMode
        end
      end
    end

    describe ":commit on a TextField" do
      it "holds typing until the field leaves the focus chain, then announces once, as the user's" do
        f = focused(Component::TextField.new)
        seen = notices(f)
        type("abc")
        assert_empty seen
        assert_equal "abc", f.value # the value is live; only the notice waits
        screen.focused = nil
        assert_equal [["abc", true]], seen
      end

      it "announces on ENTER, then lets the key bubble to the scope's default button" do
        f = focused(Component::TextField.new)
        seen = notices(f)
        type("ab")
        refute f.handle_key?(Keys::ENTER)
        assert_equal [["ab", true]], seen
      end

      it "announces on ENTER before an on_enter listener runs" do
        f = focused(Component::TextField.new)
        seen = notices(f)
        read_by_enter = nil
        f.on_enter { read_by_enter = seen.dup }
        type("ab")
        f.handle_key?(Keys::ENTER)
        assert_equal [["ab", true]], read_by_enter
      end

      it "stays silent when the held edit is typed and deleted again" do
        f = focused(Component::TextField.new)
        seen = notices(f)
        type("a")
        f.handle_key?(Keys::BACKSPACE)
        screen.focused = nil
        assert_empty seen
      end

      it "announces a write at once, and the blur after it has nothing left to say" do
        f = focused(Component::TextField.new)
        seen = notices(f)
        type("ab")
        f.value = "xyz"
        assert_equal [["xyz", false]], seen
        screen.focused = nil
        assert_equal [["xyz", false]], seen
      end

      it "announces an edit reaching a field that is not focused, which has no commit coming" do
        f = mounted(Component::TextField.new)
        seen = notices(f)
        f.handle_key?("a")
        assert_equal [["a", true]], seen
      end

      it "lets a held notice go on a switch to :eager" do
        f = focused(Component::TextField.new)
        seen = notices(f)
        type("ab")
        f.value_change_mode = :eager
        assert_equal [["ab", true]], seen
      end

      it "gives a subclass that claims ENTER no release on it" do
        submitted = nil
        klass = Class.new(Component::TextField) do
          define_method(:handle_text_input_key?) do |key|
            next super(key) unless key == Keys::ENTER

            submitted = value
            true
          end
        end
        f = focused(klass.new)
        seen = notices(f)
        type("ab")
        f.handle_key?(Keys::ENTER)
        assert_equal "ab", submitted # read live
        assert_empty seen
        screen.focused = nil
        assert_equal [["ab", true]], seen
      end
    end

    describe ":commit on a TextArea" do
      it "holds across ENTER, which types a newline, until the area is left" do
        a = focused(Component::TextArea.new)
        seen = notices(a)
        type("a")
        a.handle_key?(Keys::ENTER)
        type("b")
        assert_empty seen
        screen.focused = nil
        assert_equal [["a\nb", true]], seen
      end
    end

    describe ":lazy" do
      it "announces once the edits pause, restarting the wait per edit" do
        f = focused(Component::TextField.new)
        f.value_change_mode = :lazy
        seen = notices(f)
        type("abc")
        assert_empty seen
        assert_equal(1, queue.timers.count { !_1.cancelled? })
        queue.fire_timers
        assert_equal [["abc", true]], seen
      end

      it "announces early on a commit gesture, and the wait then has nothing to say" do
        f = focused(Component::TextField.new)
        f.value_change_mode = :lazy
        seen = notices(f)
        type("ab")
        f.handle_key?(Keys::ENTER)
        assert_equal [["ab", true]], seen
        assert(queue.timers.all?(&:cancelled?))
        queue.fire_timers
        assert_equal [["ab", true]], seen
      end

      it "cancels the wait when the field is detached" do
        f = focused(Component::TextField.new)
        f.value_change_mode = :lazy
        type("ab")
        f.parent.remove(f)
        assert(queue.timers.all?(&:cancelled?))
      end

      it "drops the wait on a switch to :commit, which waits for the gesture instead" do
        f = focused(Component::TextField.new)
        f.value_change_mode = :lazy
        seen = notices(f)
        type("ab")
        f.value_change_mode = :commit
        queue.fire_timers
        assert_empty seen
        screen.focused = nil
        assert_equal [["ab", true]], seen
      end
    end

    describe "a number field" do
      it "holds typing under :commit and announces on leaving" do
        f = focused(Component::IntegerField.new)
        seen = notices(f)
        type("42")
        assert_empty seen
        assert_equal 42, f.value
        screen.focused = nil
        assert_equal [[42, true]], seen
      end

      it "announces a write and an Up/Down step at once, being writes and not edits" do
        f = focused(Component::IntegerField.new)
        seen = notices(f)
        f.value = 4
        screen.send(:handle_key?, Keys::UP_ARROW)
        assert_equal [[4, false], [5, true]], seen
      end

      it "still reports bad input per keystroke while the value notice waits" do
        f = focused(Component::IntegerField.new)
        reports = []
        f.on_bad_input_change { reports << f.bad_input? }
        type("-")
        assert_equal [true], reports
      end

      it "runs :lazy on the same wait" do
        f = focused(Component::FloatField.new)
        f.value_change_mode = :lazy
        seen = notices(f)
        type("1.5")
        assert_empty seen
        queue.fire_timers
        assert_equal [[1.5, true]], seen
      end
    end
  end
end
