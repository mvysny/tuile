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
        screen.pane.on_tree { validatable << _1 if _1.is_a?(Component::HasValidation) }
        assert_includes validatable, field
        refute validatable.any?(Component::Label)
      end

      it "starts valid, with no message" do
        assert_nil field.error_message
      end

      it "has no invalid? predicate — a non-nil message is the verdict" do
        refute_respond_to field, :invalid?
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
        field.on_error_message_change = ->(_) { fired += 1 }
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
        field.on_error_message_change = ->(msg) { seen << msg&.to_s }
        field.error_message = "Required"
        field.error_message = "Still required"
        field.error_message = nil
        assert_equal ["Required", "Still required", nil], seen
      end

      it "is what lets a container paint the message it has cells for" do
        label = Component::Label.new
        field.on_error_message_change = ->(msg) { label.text = msg || StyledString::EMPTY }
        field.error_message = "Required"
        assert_equal "Required", label.text.to_s
      end
    end

    describe "the error ink" do
      # The field paints the *verdict*; the message needs cells it does not own.
      def row_ansi(component) = screen.buffer.row_ansi(component.rect.top)

      it "paints the field's content in Theme#error_color" do
        field.rect = Rect.new(0, 0, 10, 1)
        field.text = "bob"
        field.error_message = "Required"
        field.repaint

        assert_includes row_ansi(field), "38;5;203"
      end

      it "is gone once the verdict is cleared" do
        field.rect = Rect.new(0, 0, 10, 1)
        field.text = "bob"
        field.error_message = "Required"
        field.repaint
        field.error_message = nil
        field.repaint

        refute_includes row_ansi(field), "38;5;203"
      end

      it "tracks a theme swap with no on_theme_changed hook — it resolves at paint" do
        screen.theme = Theme::LIGHT
        field.rect = Rect.new(0, 0, 10, 1)
        field.text = "bob"
        field.error_message = "Required"
        field.repaint

        assert_includes row_ansi(field), "38;5;124"
      end

      it "reaches a composed field's inner TextField, which holds no message of its own" do
        composed = Component::IntegerField.new
        composed.rect = Rect.new(0, 0, 10, 1)
        composed.content.text = "12"
        composed.error_message = "Too small"
        composed.content.repaint

        assert_nil composed.content.error_message
        assert_includes screen.buffer.row_ansi(0), "38;5;203"
      end

      it "reaches a group's List rows the same way" do
        group = Component::RadioGroup.new
        group.items = %w[alpha beta]
        group.rect = Rect.new(0, 0, 20, 2)
        group.error_message = "Pick one"
        group.content.repaint

        assert_includes screen.buffer.row_ansi(0), "38;5;203"
      end

      it "does not leak upward: an invalid child leaves its container's chrome alone" do
        window = Component::Window.new
        window.caption = "Login"
        window.content = field
        screen.content = window
        window.rect = Rect.new(0, 0, 20, 5)
        field.error_message = "Required"
        window.repaint

        refute_includes screen.buffer.row_ansi(0), "38;5;203"
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

    describe "Component#content_fg_color" do
      it "is nil on a plain component, so nothing is tinted by default" do
        label = Component::Label.new("hi")
        assert_nil label.send(:content_fg_color)
        assert_nil label.send(:effective_content_fg_color)
      end

      it "is inherited from the nearest answering ancestor" do
        group = Component::CheckboxGroup.new
        group.error_message = "Pick one"
        assert_equal screen.theme.error_color, group.content.send(:effective_content_fg_color)
      end

      it "is final — the chain is the framework's, not a component's to override" do
        assert_raises(Error) do
          Class.new(Component) { def effective_content_fg_color = nil }.new
        end
      end
    end
  end
end
