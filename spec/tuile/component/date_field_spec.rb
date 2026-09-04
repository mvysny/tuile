# frozen_string_literal: true

require "date"

module Tuile
  describe Component::DateField do
    before { Screen.fake }
    after do
      Component::DateField.default_format = "%Y-%m-%d"
      Component::DateField.default_calendar_start = Date::GREGORIAN
      Screen.close
    end

    def field(top: 0, width: 20)
      f = Component::DateField.new
      Screen.instance.content = f
      f.rect = Rect.new(0, top, width, 1)
      Screen.instance.focused = f
      f
    end

    def type(str) = str.each_char { |ch| Screen.instance.send(:handle_key, ch) }
    def key(code) = Screen.instance.send(:handle_key, code)
    def paste(str) = Screen.instance.paste(str)
    def inner(fld) = Testing.get(Component::TextField, in: fld)
    def buffer(fld) = inner(fld).text
    def caret(fld) = inner(fld).caret

    # Move focus off the field so commit (blur) runs.
    def blur(fld)
      other = Component::Button.new("x")
      layout = Component::Layout::Absolute.new
      Screen.instance.content = layout
      layout.add(fld)
      layout.add(other)
      fld.rect = Rect.new(0, 0, 20, 1)
      other.rect = Rect.new(0, 1, 10, 1)
      Screen.instance.focused = other
    end

    it "is a focusable non-tab-stop wrapper of a single field" do
      f = field
      assert f.focusable?
      refute f.tab_stop?
      assert_equal [inner(f)], f.children
    end

    describe "value (typed HasValue seam)" do
      it "is nil and empty? on a blank buffer" do
        f = field
        assert_nil f.value
        assert f.empty?
      end

      it "derives a Date from ISO text" do
        f = field
        type("2026-09-04")
        assert_equal Date.new(2026, 9, 4), f.value
        refute f.empty?
      end

      it "value= writes the primary format and parks the caret at the end" do
        f = field
        f.value = Date.new(2026, 9, 4)
        assert_equal "2026-09-04", buffer(f)
        assert_equal 10, caret(f)
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "value = nil empties the field" do
        f = field
        f.value = Date.new(2026, 9, 4)
        f.value = nil
        assert_equal "", buffer(f)
        assert f.empty?
        assert_nil f.value
      end

      it "clear resets to nil" do
        f = field
        type("2026-09-04")
        f.clear
        assert_nil f.value
        assert f.empty?
      end

      it "accepts an unpadded ISO date" do
        f = field
        type("2026-9-4")
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "does not skip leading whitespace" do
        f = field
        inner(f).text = " 2026-09-04"
        assert_nil f.value
        assert f.bad_input?
      end

      it "rejects a leftover tail" do
        f = field
        type("2026-09-04junk")
        assert_nil f.value
        assert f.bad_input?
      end

      it "rejects a calendar-invalid day" do
        f = field
        type("2026-02-30")
        assert_nil f.value
        assert f.bad_input?
      end

      it "value= of a Time stores the civil date" do
        f = field
        f.value = Time.new(2026, 9, 4, 15, 30, 0)
        assert_equal Date.new(2026, 9, 4), f.value
        assert_equal "2026-09-04", buffer(f)
      end
    end

    describe "formats" do
      it "defaults to ISO, seeded at construction" do
        f = field
        assert_equal ["%Y-%m-%d"], f.formats
        assert f.formats.frozen?
      end

      it "accepts a String as the one-format shorthand" do
        f = field
        f.formats = "%d.%m.%Y"
        assert_equal ["%d.%m.%Y"], f.formats
        f.value = Date.new(2026, 9, 4)
        assert_equal "04.09.2026", buffer(f)
      end

      it "parses later formats and writes the primary" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y", "%m/%d/%Y"]
        inner(f).text = "4.9.2026"
        assert_equal Date.new(2026, 9, 4), f.value
        inner(f).text = "09/04/2026"
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "first match wins, so order is the disambiguation" do
        euro = field
        euro.formats = ["%d/%m/%Y", "%m/%d/%Y"]
        inner(euro).text = "04/09/2026"
        assert_equal Date.new(2026, 9, 4), euro.value

        us = Component::DateField.new
        us.formats = ["%m/%d/%Y", "%d/%m/%Y"]
        Testing.get(Component::TextField, in: us).text = "04/09/2026"
        assert_equal Date.new(2026, 4, 9), us.value
      end

      it "leaves a non-empty buffer alone" do
        f = field
        type("4.9.2026")
        f.formats = ["%d.%m.%Y", "%Y-%m-%d"]
        assert_equal "4.9.2026", buffer(f)
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "reparses under the new list, firing on_value_change when the value moves" do
        f = field
        type("04.09.2026")
        assert_nil f.value
        seen = []
        f.on_value_change = ->(v) { seen << v }
        f.formats = "%d.%m.%Y"
        assert_equal [Date.new(2026, 9, 4)], seen
      end

      it "rejects an empty list, a non-String, and nil" do
        f = field
        assert_raises(ArgumentError) { f.formats = [] }
        assert_raises(TypeError) { f.formats = nil }
        assert_raises(TypeError) { f.formats = :iso }
        assert_raises(TypeError) { f.formats = [1] }
      end

      it "rejects a format that does not round-trip" do
        f = field
        assert_raises(ArgumentError) { f.formats = "%Y-%m-%D" } # %D is mm/dd/yy
        assert_raises(ArgumentError) { f.formats = "%Y-%m" }    # partial, fills mday: 1
        assert_raises(ArgumentError) { f.formats = "%B %-d, %Y" } # strftime-only flag
      end

      it "rejects %y anywhere — the POSIX window would map 62 to 2062" do
        f = field
        e = assert_raises(ArgumentError) { f.formats = "%d/%m/%y" }
        assert_includes e.message, "%Y"
        assert_raises(ArgumentError) { f.formats = ["%Y-%m-%d", "%d.%m.%y"] }
      end

      it "rejects %x / %X / %c, which look locale-aware and are not" do
        f = field
        e = assert_raises(ArgumentError) { f.formats = "%x" }
        assert_includes e.message, "not locale-aware"
        assert_raises(ArgumentError) { f.formats = "%Y %c" }
      end

      it "DateField.default_format seeds new fields only" do
        Component::DateField.default_format = "%d.%m.%Y"
        born = Component::DateField.new
        assert_equal ["%d.%m.%Y"], born.formats
        later = (Component::DateField.default_format = "%Y-%m-%d"
                 Component::DateField.new)
        assert_equal ["%d.%m.%Y"], born.formats
        assert_equal ["%Y-%m-%d"], later.formats
      end
    end

    describe "placeholder" do
      it "derives yyyy-mm-dd from the ISO default" do
        f = field
        assert_equal "yyyy-mm-dd", f.placeholder
        assert_equal "yyyy-mm-dd", inner(f).placeholder
      end

      it "follows formats=" do
        f = field
        f.formats = "%d.%m.%Y"
        assert_equal "dd.mm.yyyy", f.placeholder
      end

      it "nil restores the derived hint; empty string suppresses it" do
        f = field
        f.placeholder = "when?"
        assert_equal "when?", f.placeholder
        f.placeholder = nil
        assert_equal "yyyy-mm-dd", f.placeholder
        f.placeholder = ""
        assert_equal "", f.placeholder
      end

      it "does not half-translate an unknown directive" do
        f = field
        f.formats = "%B %d, %Y"
        assert_nil f.placeholder
      end

      it "paints the derived hint while empty" do
        f = Component::DateField.new
        Screen.instance.content = f
        f.rect = Rect.new(0, 0, 16, 1)
        Screen.instance.repaint
        assert_equal ["yyyy-mm-dd      "], Screen.instance.buffer.region_text(f.rect)
      end
    end

    describe "no input filter" do
      it "admits every character, typed or pasted" do
        f = field
        type("xyz")
        assert_equal "xyz", buffer(f)
        assert_nil f.value
        paste("-04")
        assert_equal "xyz-04", buffer(f)
      end
    end

    describe "on_value_change" do
      it "fires once per real value change, with a Date or nil" do
        seen = []
        f = field
        f.on_value_change = ->(v) { seen << v }
        type("2026-09-04")
        assert_equal [Date.new(2026, 9, 4)], seen
        key(Keys::BACKSPACE) # "2026-09-0" does not parse
        assert_nil f.value
        assert_equal [Date.new(2026, 9, 4), nil], seen
        assert(seen.all? { |v| v.nil? || v.is_a?(Date) })
      end

      it "stays silent when a buffer edit does not change the value" do
        f = field
        type("2026-9-4")
        seen = []
        f.on_value_change = ->(v) { seen << v }
        # already a value; rewriting via value= to the same date is silent
        f.value = Date.new(2026, 9, 4)
        assert_empty seen
      end
    end

    describe "bad input" do
      it "reports a buffer that is not a date" do
        f = field
        type("xyz")
        assert f.bad_input?
        assert_equal "not a valid date", f.bad_input_message
      end

      it "empty input is not bad input" do
        f = field
        assert f.empty?
        refute f.bad_input?
        assert_nil f.bad_input_message
      end

      it "a prefix of a valid date is bad input (the fact is continuous)" do
        f = field
        type("202")
        assert f.bad_input?
        assert f.empty?
      end

      it "clears the input, not the value (which already reads nil)" do
        f = field
        type("xyz")
        f.clear
        assert_empty buffer(f)
        refute f.bad_input?
      end
    end

    describe "canonicalize on commit" do
      it "rewrites a parsed buffer in the primary format on blur" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y"]
        inner(f).text = "4.9.2026"
        blur(f)
        assert_equal "2026-09-04", buffer(f)
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "does not fire on_value_change for a rewrite that keeps the value" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y"]
        inner(f).text = "4.9.2026"
        seen = []
        f.on_value_change = ->(v) { seen << v }
        blur(f)
        assert_empty seen
        assert_equal "2026-09-04", buffer(f)
      end

      it "leaves bad input exactly as typed" do
        f = field
        type("xyz")
        blur(f)
        assert_equal "xyz", buffer(f)
        assert f.bad_input?
      end

      it "Enter commits too, then falls through when on_enter is unset" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y"]
        inner(f).text = "4.9.2026"
        # A parent that claims Enter proves fall-through.
        caught = false
        f.define_singleton_method(:handle_key) do |key|
          if key == Keys::ENTER
            caught = true
            true
          else
            super(key)
          end
        end
        key(Keys::ENTER)
        assert_equal "2026-09-04", buffer(f)
        assert caught
      end

      it "Enter commits then calls on_enter when set (and consumes)" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y"]
        inner(f).text = "4.9.2026"
        called = false
        f.on_enter = -> { called = true }
        key(Keys::ENTER)
        assert_equal "2026-09-04", buffer(f)
        assert called
      end
    end

    describe "the red well settles at commit" do
      def error_well?(component)
        Screen.instance.buffer.row_ansi(component.rect.top).include?("48;5;88")
      end

      it "does not redden a prefix while typing" do
        f = field
        type("202")
        inner(f).repaint
        assert f.bad_input?
        refute error_well?(f)
      end

      it "reddens after blur if the buffer still does not parse" do
        f = field
        type("xyz")
        blur(f)
        f.repaint
        inner(f).repaint
        assert error_well?(f)
      end

      it "clears the well on the next edit" do
        f = field
        type("xyz")
        blur(f)
        Screen.instance.focused = f
        type("1")
        inner(f).repaint
        refute error_well?(f)
      end

      it "a written error_message still reddens immediately, commit or not" do
        f = Component::DateField.new
        Screen.instance.content = f
        f.rect = Rect.new(0, 0, 20, 1)
        f.error_message = "must be in the past"
        inner(f).repaint
        assert error_well?(f)
      end
    end

    describe "the Up/Down spinner" do
      it "steps a populated field by one day" do
        f = field
        f.value = Date.new(2026, 9, 4)
        key(Keys::UP_ARROW)
        assert_equal Date.new(2026, 9, 5), f.value
        key(Keys::DOWN_ARROW)
        key(Keys::DOWN_ARROW)
        assert_equal Date.new(2026, 9, 3), f.value
      end

      it "steps an empty field to today, not today ± 1" do
        f = field
        key(Keys::UP_ARROW)
        assert_equal Date.today(Date::GREGORIAN), f.value
        f.clear
        key(Keys::DOWN_ARROW)
        assert_equal Date.today(Date::GREGORIAN), f.value
      end

      it "canonicalizes implicitly, since it writes through value=" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y"]
        inner(f).text = "4.9.2026"
        key(Keys::UP_ARROW)
        assert_equal "2026-09-05", buffer(f)
      end
    end

    describe "calendar_start" do
      it "defaults to Date::GREGORIAN, so 1582-10-10 exists" do
        f = field
        inner(f).text = "1582-10-10"
        assert_equal Date.new(1582, 10, 10, Date::GREGORIAN), f.value
      end

      it "parses 1582-10-10 as invalid under ITALY" do
        f = field
        f.calendar_start = Date::ITALY
        inner(f).text = "1582-10-10"
        assert_nil f.value
        assert f.bad_input?
      end

      it "DateField.default_calendar_start seeds new fields only" do
        Component::DateField.default_calendar_start = Date::ITALY
        born = Component::DateField.new
        assert_equal Date::ITALY, born.calendar_start
      end
    end

    describe "public surface" do
      it "exposes neither the String-typed seam nor arrow-key callbacks" do
        f = field
        %i[text text= caret caret= on_change on_key_up on_key_up= on_key_down on_key_down=].each do |m|
          refute f.respond_to?(m), "DateField should not expose ##{m}"
        end
      end
    end
  end
end
