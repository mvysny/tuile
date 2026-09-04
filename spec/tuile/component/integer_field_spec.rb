# frozen_string_literal: true

module Tuile
  describe Component::IntegerField do
    before { Screen.fake }
    after { Screen.close }

    # Attaches an integer field as the tiled content, sizes it to a single
    # 20-wide row, and focuses it (so key dispatch reaches its inner field).
    def field(top: 0, width: 20)
      f = Component::IntegerField.new
      Screen.instance.content = f
      f.rect = Rect.new(0, top, width, 1)
      Screen.instance.focused = f
      f
    end

    # Screen#handle_key is the (private) key-dispatch entry the event loop
    # drives; poke it directly to simulate typing without a real loop.
    def type(str) = str.each_char { |ch| Screen.instance.send(:handle_key, ch) }
    def key(code) = Screen.instance.send(:handle_key, code)
    # The editor is private by design; Testing.get is the sanctioned way in — a
    # spec may drive it directly (set its text, send it keys).
    def inner(fld) = Testing.get(Component::TextField, in: fld)
    def buffer(fld) = inner(fld).text
    def caret(fld) = inner(fld).caret

    it "is a focusable non-tab-stop wrapper of a single field" do
      f = field
      assert f.focusable?
      refute f.tab_stop? # the inner @field carries the tab stop, not the wrapper
      assert_equal [inner(f)], f.children
    end

    it "focusing the field forwards focus (and the caret) to its inner field" do
      f = field
      assert_same inner(f), Screen.instance.focused
      refute_nil f.cursor_position
    end

    describe "value (typed HasValue seam)" do
      it "is nil and empty? on a blank buffer" do
        f = field
        assert_nil f.value
        assert f.empty?
      end

      it "derives an Integer from the typed digits" do
        f = field
        type("42")
        assert_equal 42, f.value
        refute f.empty?
      end

      it "value= writes the buffer and parks the caret at the end" do
        f = field
        f.value = 42
        assert_equal "42", buffer(f)
        assert_equal 2, caret(f)
        assert_equal 42, f.value
      end

      it "value = nil empties the field" do
        f = field
        f.value = 7
        f.value = nil
        assert_equal "", buffer(f)
        assert f.empty?
        assert_nil f.value
      end

      it "clear resets to nil" do
        f = field
        type("9")
        f.clear
        assert_nil f.value
        assert f.empty?
      end
    end

    describe "digit filtering" do
      it "ignores letters, '.', '+', and space without moving the caret" do
        f = field
        type("12")
        at = caret(f)
        type("a")
        type(".")
        type("+")
        type(" ")
        assert_equal "12", buffer(f)
        assert_equal at, caret(f) # the drift regression: a rejected key never moves the caret
        assert_equal 12, f.value
      end

      it "backspacing to empty makes the value nil, not 0" do
        f = field
        type("7")
        assert_equal 7, f.value
        key(Keys::BACKSPACE)
        assert_equal "", buffer(f)
        assert_nil f.value
      end
    end

    # Before 0.15.0 the filter was the inner field's on_key interceptor, which
    # a paste never passes through: `abc` pasted in front of `42` left the
    # field showing "abc42" while #value silently read nil.
    describe "the filter holds against a paste, not just typing" do
      def paste(str) = Screen.instance.paste(str)

      it "drops a paste that is not a number, leaving the buffer untouched" do
        f = field
        type("42")
        at = caret(f)
        paste("abc")
        assert_equal "42", buffer(f)
        assert_equal at, caret(f)
        assert_equal 42, f.value
      end

      it "drops a partly-numeric paste whole rather than sieving out the digits" do
        f = field
        paste("12abc34")
        assert_equal "", buffer(f)
        assert_nil f.value
      end

      it "accepts a numeric paste at the caret" do
        f = field
        type("42")
        inner(f).caret = 0
        paste("-9")
        assert_equal "-942", buffer(f)
        assert_equal(-942, f.value)
      end

      it "rejects a paste that would make the buffer un-typeable" do
        f = field
        type("42")
        inner(f).caret = 1 # a minus here would give "4-2"
        paste("-")
        assert_equal "42", buffer(f)
      end
    end

    describe "the leading minus sign" do
      it "a lone '-' is a nil value, not 0" do
        f = field
        type("-")
        assert_equal "-", buffer(f)
        assert_nil f.value
      end

      it "builds a negative number once a digit follows" do
        f = field
        type("-5")
        assert_equal "-5", buffer(f)
        assert_equal(-5, f.value)
      end

      it "rejects '-' in the middle of a number" do
        f = field
        type("5")
        at = caret(f)
        type("-")
        assert_equal "5", buffer(f)
        assert_equal at, caret(f)
      end

      it "accepts '-' only at caret 0" do
        f = field
        type("5")
        key(Keys::HOME)
        type("-")
        assert_equal "-5", buffer(f)
        assert_equal(-5, f.value)
      end

      it "rejects a second '-' when one already leads" do
        f = field
        type("-5")
        key(Keys::HOME)
        type("-")
        assert_equal "-5", buffer(f)
      end
    end

    describe "on_value_change" do
      it "fires once per real value change, with an Integer or nil (never a String)" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
        type("42")
        key(Keys::BACKSPACE) # "42" -> "4"
        key(Keys::BACKSPACE) # "4"  -> ""
        assert_equal [4, 42, 4, nil], seen
        assert(seen.all? { |v| v.nil? || v.is_a?(Integer) })
      end

      it "does not fire while a transient '-' leaves the value nil" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
        type("-")  # value still nil -> silent
        type("5")  # now -5 -> fires
        assert_equal [-5], seen
      end

      it "stays silent when a buffer edit doesn't change the value ('7' -> '07')" do
        f = field
        type("7") # value 7
        seen = []
        f.on_value_change = ->(v) { seen << v }
        key(Keys::HOME)
        type("0") # buffer "07", value still 7
        assert_equal "07", buffer(f)
        assert_equal 7, f.value
        assert_empty seen
      end
    end

    describe "bad input (the fact on_value_change cannot carry)" do
      it "reports the lone '-' the filter has to admit" do
        f = field
        type("-")
        assert f.bad_input?
        assert_equal "not a whole number", f.bad_input_message
      end

      it "is the only channel that speaks when the value does not move" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
        refute f.bad_input?
        type("-")         # "" -> "-": nil before, nil after...
        assert_empty seen # ...so the value seam has nothing to diff
        assert f.bad_input?
      end

      it "empty input is not bad input, or every blank optional field blocks a save" do
        f = field
        assert f.empty?
        refute f.bad_input?
        assert_nil f.bad_input_message
      end

      it "answers what empty? cannot: empty of value, full of glyphs" do
        f = field
        type("-")
        assert f.empty?
        assert f.bad_input?
        assert_equal "-", buffer(f)
      end

      it "clears the input, not the value (which already reads nil)" do
        f = field
        type("-")
        f.clear
        assert_empty buffer(f)
        refute f.bad_input?
      end

      it "says nothing about a buffer that parses" do
        f = field
        type("-42")
        refute f.bad_input?
        assert_nil f.bad_input_message
      end
    end

    it "drives the spinner off the purpose-fit arrow seams" do
      f = field
      refute_nil inner(f).on_key_up
      refute_nil inner(f).on_key_down
    end

    describe "the Up/Down spinner" do
      it "Up increments and Down decrements the value" do
        f = field
        f.value = 5
        key(Keys::UP_ARROW)
        assert_equal 6, f.value
        key(Keys::DOWN_ARROW)
        key(Keys::DOWN_ARROW)
        assert_equal 4, f.value
      end

      it "steps from an empty field treating it as 0" do
        f = field
        key(Keys::UP_ARROW)
        assert_equal 1, f.value
      end

      it "Down on an empty field goes negative" do
        f = field
        key(Keys::DOWN_ARROW)
        assert_equal(-1, f.value)
        assert_equal "-1", buffer(f)
      end

      it "fires on_value_change as it steps" do
        seen = []
        f = field
        f.value = 2
        f.on_value_change = ->(v) { seen << v }
        key(Keys::UP_ARROW)
        key(Keys::UP_ARROW)
        assert_equal [3, 4], seen
      end
    end

    describe "public surface" do
      it "exposes neither the String-typed seam nor arrow-key callbacks" do
        f = field
        %i[text text= caret caret= on_change on_key_up on_key_up= on_key_down on_key_down=].each do |m|
          refute f.respond_to?(m), "IntegerField should not expose ##{m}"
        end
      end

      it "still delegates on_enter (submit) to the inner field" do
        f = field
        cb = -> {}
        f.on_enter = cb
        assert_same cb, inner(f).on_enter
        assert_same cb, f.on_enter
      end
    end

    context "placeholder" do
      # An app should not have to know this widget is a TextField in a trenchcoat.
      it "forwards to the inner field, which paints it while empty" do
        f = Component::IntegerField.new
        Screen.instance.content = f
        f.rect = Rect.new(0, 0, 12, 1)
        f.placeholder = "0-65535"
        assert_equal "0-65535", f.placeholder
        assert_equal "0-65535", inner(f).placeholder
        Screen.instance.repaint
        assert_equal ["0-65535     "], Screen.instance.buffer.region_text(f.rect)
      end

      it "gives way to a value and returns when cleared" do
        f = Component::IntegerField.new
        Screen.instance.content = f
        f.rect = Rect.new(0, 0, 12, 1)
        f.placeholder = "0-65535"
        f.value = 42
        Screen.instance.repaint
        assert_equal ["42          "], Screen.instance.buffer.region_text(f.rect)
        f.clear
        Screen.instance.repaint
        assert_equal ["0-65535     "], Screen.instance.buffer.region_text(f.rect)
      end
    end
  end
end
