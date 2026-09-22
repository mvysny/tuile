# frozen_string_literal: true

module Tuile
  describe Component::HasValidation do
    before { Screen.fake }
    after { Screen.close }

    let(:screen) { Screen.instance }
    let(:field) { Component::TextField.new }

    describe "the seam" do
      it "is included by HasValue, so every field carries it" do
        [Component::TextField, Component::TextArea, Component::PasswordField, Component::Checkbox,
         Component::CheckboxGroup, Component::RadioGroup, Component::Select, Component::ComboBox,
         Component::IntegerField, Component::FloatField, Component::BigDecimalField].each do |klass|
          assert klass.include?(Component::HasValidation), "#{klass} does not include HasValidation"
        end
      end

      it "is findable by a tree walk, which is what a locator needs" do
        pane = Component::Layout::Vertical.new
        pane.add(Component::Label.new("Name"))
        pane.add(field)
        screen.content = pane

        validatable = []
        screen.pane.walk_tree { validatable << _1 if _1.is_a?(Component::HasValidation) }
        assert_includes validatable, field
        refute validatable.any?(Component::Label)
      end

      it "starts valid, with no message" do
        assert_nil field.error_message
      end

      it "has no invalid? predicate — a non-nil message is the verdict" do
        refute_respond_to field, :invalid?
      end

      it "shows the verdict, there being no second channel on a plain field" do
        assert_nil field.shown_message
        field.error_message = "Required"
        assert_equal "Required", field.shown_message.to_s
      end

      it "keeps a ProgressBar out: a display widget is not a field" do
        refute Component::ProgressBar.include?(Component::HasValidation)
      end
    end

    describe "#error_message=" do
      it "parses a String, like caption=" do
        field.error_message = "Required"
        assert_instance_of StyledString, field.error_message
        assert_equal "Required", field.error_message.to_s
      end

      it "keeps a StyledString as-is" do
        msg = StyledString.styled("Required", bold: true)
        field.error_message = msg
        assert_equal msg, field.error_message
      end

      it "accepts an empty message — a verdict with nothing to say is still a verdict" do
        field.error_message = ""
        refute_nil field.error_message
        assert_equal "", field.error_message.to_s
      end

      it "clears on nil" do
        field.error_message = "Required"
        field.error_message = nil
        assert_nil field.error_message
      end

      it "invalidates the field" do
        screen.content = field
        screen.invalidated_clear
        field.error_message = "Required"
        assert screen.invalidated?(field)
      end

      it "is a no-op when unchanged — no repaint, no listener" do
        screen.content = field
        field.error_message = "Required"
        fired = 0
        field.on_error_message_change { fired += 1 }
        screen.invalidated_clear

        field.error_message = "Required"
        refute screen.invalidated?(field)
        assert_equal 0, fired
      end

      it "does not raise on a detached field — a form is validated before it is mounted" do
        detached = Component::TextField.new
        refute_predicate detached, :attached?
        detached.error_message = "Required"
        assert_equal "Required", detached.error_message.to_s
      end
    end

    describe "#on_error_message_change" do
      it "fires with the new message, and with nil on clear" do
        seen = []
        field.on_error_message_change { |e| seen << e.error_message&.to_s }
        field.error_message = "Required"
        field.error_message = "Still required"
        field.error_message = nil
        assert_equal ["Required", "Still required", nil], seen
      end

      it "is what lets a container paint the message it has cells for" do
        label = Component::Label.new
        field.on_error_message_change { |e| label.text = e.error_message || StyledString::EMPTY }
        field.error_message = "Required"
        assert_equal "Required", label.text.to_s
      end
    end

    describe "the error well" do
      # The field paints the *verdict*; the message needs cells it does not own.
      def row_ansi(component) = Testing.paint(component).row_ansi(0)

      it "paints the field's background in Theme#error_bg_color" do
        Testing.place(field, Rect.new(0, 0, 10, 1))
        field.text = "bob"
        field.error_message = "Required"

        assert_includes row_ansi(field), "48;5;88"
      end

      it "uses Theme#error_active_bg_color while the field has focus" do
        mount_at(field, Rect.new(0, 0, 10, 1))
        screen.focused = field
        field.error_message = "Required"

        assert_includes row_ansi(field), "48;5;95"
      end

      # The gap the foreground ink could not cover, and the one that matters:
      # "required" is exactly the rule that fires on a field with no glyphs.
      it "shows on an empty field" do
        Testing.place(field, Rect.new(0, 0, 10, 1))
        field.error_message = "Required"

        assert_includes row_ansi(field), "48;5;88"
      end

      it "is gone once the verdict is cleared, back to the ordinary well" do
        Testing.place(field, Rect.new(0, 0, 10, 1))
        field.text = "bob"
        field.error_message = "Required"
        assert_includes row_ansi(field), "48;5;88"
        field.error_message = nil

        refute_includes row_ansi(field), "48;5;88"
        assert_includes row_ansi(field), "48;5;238"
      end

      it "tracks a theme swap with no handle_theme_changed hook — it resolves at paint" do
        screen.theme = Theme::LIGHT
        Testing.place(field, Rect.new(0, 0, 10, 1))
        field.error_message = "Required"

        assert_includes row_ansi(field), "48;5;224"
      end

      it "reaches a composed field's inner TextField, which holds no message of its own" do
        composed = Component::IntegerField.new
        Testing.place(composed, Rect.new(0, 0, 10, 1))
        Testing.get(Component::TextField, in: composed).text = "12"
        composed.error_message = "Too small"

        assert_nil Testing.get(Component::TextField, in: composed).error_message
        assert_includes row_ansi(composed), "48;5;88"
      end

      it "reaches a group's List rows the same way" do
        group = Component::RadioGroup.new
        group.items = %w[alpha beta]
        Testing.place(group, Rect.new(0, 0, 20, 2))
        group.error_message = "Pick one"
        painted = Testing.paint(group.list)

        assert_includes painted.row_ansi(0), "48;5;88"
      end

      # A Checkbox declares no well of its own, so this is the only background
      # it ever paints — and the chain delivers it with no Checkbox code.
      it "reaches a Checkbox, which has no well when valid" do
        box = Component::Checkbox.new("I accept")
        Testing.place(box, Rect.new(0, 0, 20, 1))
        refute_includes Testing.paint(box).row_ansi(0), "48;5;88"

        box.error_message = "You must accept"
        assert_includes Testing.paint(box).row_ansi(0), "48;5;88"
      end

      # Outside its extent the widget is not there — ambient_bg_color, which
      # skips this level exactly as it skips default_bg_color.
      it "stops at the extent, leaving the dead tail alone" do
        box = Component::Checkbox.new("ok")
        Testing.place(box, Rect.new(0, 0, 40, 1))
        box.error_message = "nope"
        buffer = Testing.paint(box)

        painted = box.extent.width
        assert_includes buffer.region_ansi(Rect.new(0, 0, painted, 1)).first, "48;5;88"
        refute_includes buffer.region_ansi(Rect.new(painted, 0, 40 - painted, 1)).first, "48;5;88"
      end

      # An app tinting a panel must not be able to switch the signal off.
      it "wins over an app's own bg_color" do
        Testing.place(field, Rect.new(0, 0, 10, 1))
        field.bg_color = Color::BLUE
        field.error_message = "Required"

        assert_includes row_ansi(field), "48;5;88"
      end

      it "does not leak upward: an invalid child leaves its container's chrome alone" do
        window = Component::Window.new
        window.caption = "Login"
        window.content = field
        mount_at(window, Rect.new(0, 0, 20, 5))
        field.error_message = "Required"
        painted = Testing.paint(window)

        refute_includes painted.row_ansi(0), "48;5;88"
      end
    end

    describe "bad input paints the well too" do
      def row_ansi(component) = Testing.paint(component).row_ansi(0)

      it "marks an IntegerField holding input its value cannot represent" do
        int = Component::IntegerField.new
        Testing.place(int, Rect.new(0, 0, 10, 1))
        Testing.get(Component::TextField, in: int).text = "-"

        assert int.bad_input?
        assert_nil int.error_message
        assert_includes row_ansi(int), "48;5;88"
      end

      it "clears as soon as the input parses" do
        int = Component::IntegerField.new
        Testing.place(int, Rect.new(0, 0, 10, 1))
        Testing.get(Component::TextField, in: int).text = "-4"

        refute_includes row_ansi(int), "48;5;88"
      end

      it "leaves a field with no bad-input report to the verdict alone" do
        Testing.place(field, Rect.new(0, 0, 10, 1))
        field.text = "anything"

        refute_includes row_ansi(field), "48;5;88"
      end
    end

    describe "#inspect_details" do
      # So a Testing.get failure dump names the field that is already flagged.
      it "shows the message, and nothing while the field is valid" do
        field = Component::TextField.new
        assert_equal "#<Tuile::Component::TextField rect=(0,0 0x0) value=\"\">", field.inspect

        field.error_message = "Required"
        assert_equal "#<Tuile::Component::TextField rect=(0,0 0x0) error_message=\"Required\" value=\"\">",
                     field.inspect
      end
    end

    describe "Component#error_bg_color" do
      it "is nil on a plain component, so nothing is tinted by default" do
        assert_nil Component::Label.new("hi").send(:error_bg_color)
      end

      it "answers the token for the state the field is in, and nothing while valid" do
        assert_nil field.send(:error_bg_color)

        field.error_message = "Required"
        assert_equal screen.theme.error_bg_color, field.send(:error_bg_color)
      end

      it "is protected — the framework paints with it, an app never reads it" do
        refute_respond_to field, :error_bg_color
      end
    end
  end
end
