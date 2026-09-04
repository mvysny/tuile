# frozen_string_literal: true

module Tuile
  describe Component::FloatField do
    before { Screen.fake }
    after { Screen.close }

    # Attaches a float field as the tiled content, sizes it to a single
    # 20-wide row, and focuses it (so key dispatch reaches its inner field).
    def field(top: 0, width: 20)
      f = Component::FloatField.new
      Screen.instance.content = f
      f.rect = Rect.new(0, top, width, 1)
      Screen.instance.focused = f
      f
    end

    # Screen#handle_key is the (private) key-dispatch entry the event loop
    # drives; poke it directly to simulate typing without a real loop.
    def type(str) = str.each_char { |ch| Screen.instance.send(:handle_key, ch) }
    def key(code) = Screen.instance.send(:handle_key, code)
    def inner(fld) = fld.content
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

      it "derives a Float from the typed digits" do
        f = field
        type("19.99")
        assert_in_delta 19.99, f.value
        assert_kind_of Float, f.value
        refute f.empty?
      end

      it "reads a buffer with no decimal point as a Float" do
        f = field
        type("42")
        assert_equal 42.0, f.value
        assert_kind_of Float, f.value
      end

      it "value= writes the buffer and parks the caret at the end" do
        f = field
        f.value = 19.99
        assert_equal "19.99", buffer(f)
        assert_equal 5, caret(f)
        assert_in_delta 19.99, f.value
      end

      it "value= coerces an Integer to a Float (so 3 shows as '3.0')" do
        f = field
        f.value = 3
        assert_equal "3.0", buffer(f)
        assert_equal 3.0, f.value
      end

      it "value = nil empties the field" do
        f = field
        f.value = 7.5
        f.value = nil
        assert_equal "", buffer(f)
        assert f.empty?
        assert_nil f.value
      end

      it "clear resets to nil" do
        f = field
        type("9.5")
        f.clear
        assert_nil f.value
        assert f.empty?
      end

      it "round-trips a magnitude Float#to_s writes in exponent form" do
        f = field
        f.value = 1e-5
        assert_equal "1.0e-05", buffer(f) # no key types an 'e', but the parse reads one
        assert_in_delta 1e-5, f.value, 1e-12
      end

      it "refuses a non-finite value rather than silently reading back nil" do
        f = field
        assert_raises(ArgumentError) { f.value = Float::NAN }
        assert_raises(ArgumentError) { f.value = Float::INFINITY }
        assert_raises(TypeError) { f.value = [] }
      end
    end

    describe "digit filtering" do
      it "ignores letters and space without moving the caret" do
        f = field
        type("1.5")
        at = caret(f)
        type("a")
        type(",")
        type(" ")
        assert_equal "1.5", buffer(f)
        assert_equal at, caret(f) # a rejected key never moves the caret
        assert_in_delta 1.5, f.value
      end

      it "types the exponent it can display, so a shown value stays editable" do
        f = field
        type("1.5e+3")
        assert_equal "1.5e+3", buffer(f)
        assert_in_delta 1500.0, f.value
      end

      it "backspacing to empty makes the value nil, not 0.0" do
        f = field
        type("7")
        assert_equal 7.0, f.value
        key(Keys::BACKSPACE)
        assert_equal "", buffer(f)
        assert_nil f.value
      end
    end

    # Before 0.15.0 the filter was the inner field's on_key interceptor, which
    # a paste never passes through — so a European "1,5" landed whole and read
    # back as nil.
    describe "the filter holds against a paste, not just typing" do
      def paste(str) = Screen.instance.paste(str)

      it "drops a comma-decimal paste rather than sieving it into a wrong number" do
        f = field
        paste("1,5")
        assert_equal "", buffer(f) # emphatically not "15"
        assert_nil f.value
      end

      it "drops a paste that is not a number, leaving the buffer untouched" do
        f = field
        type("1.5")
        paste("abc")
        assert_equal "1.5", buffer(f)
        assert_in_delta 1.5, f.value
      end

      it "accepts a numeric paste, exponent included" do
        f = field
        paste("-2.5e3")
        assert_equal "-2.5e3", buffer(f)
        assert_in_delta(-2500.0, f.value)
      end

      it "rejects a second decimal point" do
        f = field
        type("1.5")
        paste(".7")
        assert_equal "1.5", buffer(f)
      end
    end

    describe "the decimal point" do
      it "accepts exactly one point, anywhere" do
        f = field
        type("1.5")
        at = caret(f)
        type(".")
        assert_equal "1.5", buffer(f)
        assert_equal at, caret(f)
      end

      it "reads a trailing point as the number typed so far (no blink to nil)" do
        f = field
        type("1.")
        assert_equal "1.", buffer(f)
        assert_equal 1.0, f.value
      end

      it "reads a leading point as a fraction" do
        f = field
        type(".5")
        assert_equal ".5", buffer(f)
        assert_in_delta 0.5, f.value
      end

      it "a lone '.' is a nil value, not 0.0" do
        f = field
        type(".")
        assert_equal ".", buffer(f)
        assert_nil f.value
      end
    end

    describe "the leading minus sign" do
      it "a lone '-' is a nil value, not 0.0" do
        f = field
        type("-")
        assert_equal "-", buffer(f)
        assert_nil f.value
      end

      it "builds a negative number once digits follow" do
        f = field
        type("-0.25")
        assert_equal "-0.25", buffer(f)
        assert_in_delta(-0.25, f.value)
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
        assert_equal(-5.0, f.value)
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
      it "fires once per real value change, with a Float or nil (never a String)" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
        type("4.5")
        key(Keys::BACKSPACE) # "4.5" -> "4."
        key(Keys::BACKSPACE) # "4."  -> "4"
        key(Keys::BACKSPACE) # "4"   -> ""
        assert_equal [4.0, 4.5, 4.0, nil], seen # "4." and "4" both read 4.0, so the pair fires once
        assert(seen.all? { |v| v.nil? || v.is_a?(Float) })
      end

      it "does not fire while a transient '-' leaves the value nil" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
        type("-")   # value still nil -> silent
        type("0.5") # now -0.5 -> fires per digit
        assert_equal [-0.0, -0.5], seen
      end

      it "stays silent when a buffer edit doesn't change the value ('7' -> '07')" do
        f = field
        type("7") # value 7.0
        seen = []
        f.on_value_change = ->(v) { seen << v }
        key(Keys::HOME)
        type("0") # buffer "07", value still 7.0
        assert_equal "07", buffer(f)
        assert_equal 7.0, f.value
        assert_empty seen
      end
    end

    describe "bad input (the fact on_value_change cannot carry)" do
      it "reports every half-typed buffer the filter has to admit" do
        ["-", ".", "-.", "e", "1e", "1.0e-"].each do |half|
          f = field
          type(half)
          assert_equal half, buffer(f)
          assert f.bad_input?, "#{half.inspect} should report bad input"
          assert_equal "not a number", f.bad_input_message
        end
      end

      it "is the only channel that speaks when the value does not move" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
        refute f.bad_input?
        type("1e")        # "1" reads 1.0, "1e" reads nil...
        assert_equal [1.0, nil], seen
        seen.clear
        type("-")         # "1e" -> "1e-": nil before, nil after...
        assert_empty seen # ...so the value seam has nothing to diff
        assert f.bad_input?
      end

      it "empty input is not bad input, or every blank optional field blocks a save" do
        f = field
        assert f.empty?
        refute f.bad_input?
        assert_nil f.bad_input_message
      end

      it "says nothing about the half-typed buffers that do parse" do
        ["1.", ".5", "1.0e-5"].each do |good|
          f = field
          type(good)
          refute f.bad_input?, "#{good.inspect} parses, so it is not bad input"
        end
      end

      it "clears the input, not the value (which already reads nil)" do
        f = field
        type("1e")
        f.clear
        assert_empty buffer(f)
        refute f.bad_input?
      end
    end

    describe "the Up/Down spinner" do
      it "Up increments and Down decrements the value by one" do
        f = field
        f.value = 5.5
        key(Keys::UP_ARROW)
        assert_in_delta 6.5, f.value
        key(Keys::DOWN_ARROW)
        key(Keys::DOWN_ARROW)
        assert_in_delta 4.5, f.value
      end

      it "steps from an empty field treating it as 0.0" do
        f = field
        key(Keys::UP_ARROW)
        assert_equal 1.0, f.value
        assert_equal "1.0", buffer(f)
      end

      it "Down on an empty field goes negative" do
        f = field
        key(Keys::DOWN_ARROW)
        assert_equal(-1.0, f.value)
        assert_equal "-1.0", buffer(f)
      end

      it "fires on_value_change as it steps" do
        seen = []
        f = field
        f.value = 2.0
        f.on_value_change = ->(v) { seen << v }
        key(Keys::UP_ARROW)
        key(Keys::UP_ARROW)
        assert_equal [3.0, 4.0], seen
      end
    end

    describe "public surface" do
      it "exposes neither the String-typed seam nor arrow-key callbacks" do
        f = field
        %i[text text= caret caret= on_change on_key_up on_key_up= on_key_down on_key_down=].each do |m|
          refute f.respond_to?(m), "FloatField should not expose ##{m}"
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
        f = Component::FloatField.new
        Screen.instance.content = f
        f.rect = Rect.new(0, 0, 12, 1)
        f.placeholder = "0.0-1.0"
        assert_equal "0.0-1.0", f.placeholder
        assert_equal "0.0-1.0", f.content.placeholder
        Screen.instance.repaint
        assert_equal ["0.0-1.0     "], Screen.instance.buffer.region_text(f.rect)
      end

      it "gives way to a value and returns when cleared" do
        f = Component::FloatField.new
        Screen.instance.content = f
        f.rect = Rect.new(0, 0, 12, 1)
        f.placeholder = "0.0-1.0"
        f.value = 0.5
        Screen.instance.repaint
        assert_equal ["0.5         "], Screen.instance.buffer.region_text(f.rect)
        f.clear
        Screen.instance.repaint
        assert_equal ["0.0-1.0     "], Screen.instance.buffer.region_text(f.rect)
      end
    end
  end
end
