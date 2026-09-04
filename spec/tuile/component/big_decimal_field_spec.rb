# frozen_string_literal: true

module Tuile
  describe Component::BigDecimalField do
    before { Screen.fake }
    after { Screen.close }

    # Attaches a decimal field as the tiled content, sizes it to a single
    # 20-wide row, and focuses it (so key dispatch reaches its inner field).
    def field(top: 0, width: 20)
      f = Component::BigDecimalField.new
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
    def big(str) = BigDecimal(str)

    it "is a focusable non-tab-stop wrapper of a single field" do
      f = field
      assert f.focusable?
      refute f.tab_stop? # the inner @field carries the tab stop, not the wrapper
      assert_equal [inner(f)], f.children
    end

    describe "value (typed HasValue seam)" do
      it "is nil and empty? on a blank buffer" do
        f = field
        assert_nil f.value
        assert f.empty?
      end

      it "derives an exact BigDecimal from the typed digits" do
        f = field
        type("0.1")
        assert_kind_of BigDecimal, f.value
        assert_equal big("0.1"), f.value
        assert_equal big("0.3"), f.value * 3 # the whole point: a Float would give 0.30000000000000004
      end

      it "value= writes plain notation, not BigDecimal#to_s's engineering form" do
        f = field
        f.value = big("19.99")
        assert_equal "19.99", buffer(f) # BigDecimal#to_s would be "0.1999e2"
        assert_equal 5, caret(f)
        assert_equal big("19.99"), f.value
      end

      it "writes a small magnitude without an exponent, and reads it back" do
        f = field
        f.value = big("1e-5")
        assert_equal "0.00001", buffer(f)
        assert_equal big("1e-5"), f.value
      end

      it "coerces an Integer and a String" do
        f = field
        f.value = 3
        assert_equal "3.0", buffer(f)
        f.value = "19.99"
        assert_equal big("19.99"), f.value
      end

      it "refuses a Float rather than storing an inexact decimal" do
        f = field
        error = assert_raises(ArgumentError) { f.value = 19.99 }
        assert_includes error.message, "not exact"
        assert_nil f.value # the buffer is untouched by the refusal
      end

      it "refuses a non-finite value rather than silently reading back nil" do
        f = field
        assert_raises(ArgumentError) { f.value = BigDecimal::NAN }
        assert_raises(ArgumentError) { f.value = BigDecimal::INFINITY }
        assert_raises(ArgumentError) { f.value = "nonsense" }
        assert_raises(TypeError) { f.value = [] }
      end

      it "value = nil empties the field" do
        f = field
        f.value = big("7.5")
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
    end

    describe "the buffer stays as typed" do
      it "keeps a trailing zero the value alone would lose" do
        f = field
        type("19.90")
        assert_equal "19.90", buffer(f) # value.to_s("F") would render "19.9"
        assert_equal big("19.9"), f.value
      end

      it "keeps leading zeros" do
        f = field
        type("007")
        assert_equal "007", buffer(f)
        assert_equal big("7"), f.value
      end
    end

    describe "half-typed buffers (normalized before parsing)" do
      it "reads a trailing point as the number typed so far" do
        f = field
        type("1.")
        assert_equal "1.", buffer(f) # bigdecimal 3.1 raises on BigDecimal("1.")
        assert_equal big("1"), f.value
      end

      it "reads a leading point as a fraction" do
        f = field
        type(".5")
        assert_equal big("0.5"), f.value
      end

      it "reads a negative leading point as a fraction" do
        f = field
        type("-.5")
        assert_equal big("-0.5"), f.value
      end

      it "a lone '.' or '-' is nil, not zero" do
        f = field
        type(".")
        assert_nil f.value
        key(Keys::BACKSPACE)
        type("-")
        assert_nil f.value
      end
    end

    describe "character filtering" do
      it "ignores letters, a second '.', '+' and space without moving the caret" do
        f = field
        type("1.5")
        at = caret(f)
        type("a")
        type(".")
        type("+")
        type(" ")
        assert_equal "1.5", buffer(f)
        assert_equal at, caret(f) # a rejected key never moves the caret
      end

      it "accepts '-' only at caret 0, and only once" do
        f = field
        type("5")
        type("-")
        assert_equal "5", buffer(f)
        key(Keys::HOME)
        type("-")
        assert_equal "-5", buffer(f)
        key(Keys::HOME)
        type("-")
        assert_equal "-5", buffer(f)
        assert_equal big("-5"), f.value
      end
    end

    # Before 0.15.0 the filter was the inner field's on_key interceptor, which
    # a paste never passes through — so "$19.99" landed whole and read as nil.
    describe "the filter holds against a paste, not just typing" do
      def paste(str) = Screen.instance.paste(str)

      it "drops a currency-decorated paste rather than sieving out a price" do
        f = field
        paste("$19.99")
        assert_equal "", buffer(f) # emphatically not "19.99"
        assert_nil f.value
      end

      it "accepts a plain decimal paste" do
        f = field
        paste("19.99")
        assert_equal "19.99", buffer(f)
        assert_equal big("19.99"), f.value
      end

      it "drops a thousands-separated paste whole" do
        f = field
        paste("1,234.50")
        assert_equal "", buffer(f)
        assert_nil f.value
      end
    end

    describe "on_value_change" do
      it "fires once per real value change, with a BigDecimal or nil" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
        type("1.5")
        key(Keys::BACKSPACE) # "1.5" -> "1."
        assert_equal [big("1"), big("1.5"), big("1")], seen
        assert(seen.all? { |v| v.is_a?(BigDecimal) })
      end

      it "stays silent when a buffer edit doesn't change the value ('1.0' -> '1.00')" do
        f = field
        type("1.0")
        seen = []
        f.on_value_change = ->(v) { seen << v }
        type("0") # buffer "1.00", numerically equal to "1.0"
        assert_equal "1.00", buffer(f)
        assert_empty seen
      end
    end

    describe "bad input (the fact on_value_change cannot carry)" do
      it "reports the half-typed buffers the filter has to admit" do
        ["-", ".", "-."].each do |half|
          f = field
          type(half)
          assert_equal half, buffer(f)
          assert f.bad_input?, "#{half.inspect} should report bad input"
          assert_equal "not a decimal number", f.bad_input_message
        end
      end

      it "is the only channel that speaks when the value does not move" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
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

      it "says nothing about a buffer that parses, half-typed or not" do
        ["1.", ".5", "19.90"].each do |good|
          f = field
          type(good)
          refute f.bad_input?, "#{good.inspect} parses, so it is not bad input"
        end
      end

      it "clears the input, not the value (which already reads nil)" do
        f = field
        type("-")
        f.clear
        assert_empty buffer(f)
        refute f.bad_input?
      end
    end

    describe "the Up/Down spinner" do
      it "steps by one, exactly" do
        f = field
        f.value = big("19.99")
        key(Keys::UP_ARROW)
        assert_equal big("20.99"), f.value
        assert_equal "20.99", buffer(f)
        key(Keys::DOWN_ARROW)
        key(Keys::DOWN_ARROW)
        assert_equal big("18.99"), f.value
      end

      it "steps from an empty field treating it as zero" do
        f = field
        key(Keys::DOWN_ARROW)
        assert_equal big("-1"), f.value
      end
    end

    describe "public surface" do
      it "exposes neither the String-typed seam nor arrow-key callbacks" do
        f = field
        %i[text text= caret caret= on_change on_key_up on_key_up= on_key_down on_key_down=].each do |m|
          refute f.respond_to?(m), "BigDecimalField should not expose ##{m}"
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

    # The packaging half of the decision: bigdecimal is Tuile's one optional
    # dependency, and both halves of "optional" have to hold — no gemspec
    # entry, and no load in a process that never names the component.
    describe "the optional dependency" do
      it "is not a runtime dependency of the gem" do
        spec = Gem::Specification.load(File.expand_path("../../../tuile.gemspec", __dir__))
        refute_includes spec.runtime_dependencies.map(&:name), "bigdecimal"
      end

      it "stays unloaded when a host app eager-loads every Zeitwerk loader" do
        lib = File.expand_path("../../../lib", __dir__)
        script = 'require "tuile"; Zeitwerk::Loader.eager_load_all; ' \
                 "puts $LOADED_FEATURES.grep(/bigdecimal/).inspect"
        # No shell: `$LOADED_FEATURES` would be expanded away by it.
        out = IO.popen([RbConfig.ruby, "-I#{lib}", "-e", script], err: %i[child out], &:read)
        assert_equal "[]", out.strip, "eager_load_all pulled in bigdecimal: #{out}"
      end
    end

    context "placeholder" do
      # An app should not have to know this widget is a TextField in a trenchcoat.
      it "forwards to the inner field, which paints it while empty" do
        f = Component::BigDecimalField.new
        Screen.instance.content = f
        f.rect = Rect.new(0, 0, 12, 1)
        f.placeholder = "0.00"
        assert_equal "0.00", f.placeholder
        assert_equal "0.00", inner(f).placeholder
        Screen.instance.repaint
        assert_equal ["0.00        "], Screen.instance.buffer.region_text(f.rect)
      end

      it "gives way to a value and returns when cleared" do
        f = Component::BigDecimalField.new
        Screen.instance.content = f
        f.rect = Rect.new(0, 0, 12, 1)
        f.placeholder = "0.00"
        f.value = BigDecimal("1.5")
        Screen.instance.repaint
        assert_equal ["1.5         "], Screen.instance.buffer.region_text(f.rect)
        f.clear
        Screen.instance.repaint
        assert_equal ["0.00        "], Screen.instance.buffer.region_text(f.rect)
      end
    end
  end
end
