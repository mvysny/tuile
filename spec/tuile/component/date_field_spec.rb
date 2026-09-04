# frozen_string_literal: true

module Tuile
  describe Component::DateField do
    before { Screen.fake }
    # Nothing to restore: the conventions live on the screen, which the next
    # `Screen.fake` replaces. {FakeScreen} pins them to {Locale::ISO}.
    after { Screen.close }

    # Attaches a date field as the tiled content, sizes it to a single 20-wide
    # row, and focuses it (so key dispatch reaches its inner editor).
    def field(width: 20)
      f = Component::DateField.new
      Screen.instance.content = f
      f.rect = Rect.new(0, 0, width, 1)
      Screen.instance.focused = f
      f
    end

    # Screen#handle_key is the (private) key-dispatch entry the event loop
    # drives; poke it directly to simulate typing without a real loop.
    def type(str) = str.each_char { |ch| Screen.instance.send(:handle_key, ch) }
    def key(code) = Screen.instance.send(:handle_key, code)
    # The editor is private by design; Testing.get is the sanctioned way in.
    def inner(fld) = Testing.get(Component::TextField, in: fld)
    def buffer(fld) = inner(fld).text
    # Blur: dropping focus takes the field off the focus chain, which is the
    # commit point.
    def blur = (Screen.instance.focused = nil)

    it "is a focusable non-tab-stop wrapper of a single editor" do
      f = field
      assert f.focusable?
      refute f.tab_stop? # the inner editor carries the tab stop, not the wrapper
      assert_equal [inner(f)], f.children
    end

    it "focusing the field forwards focus (and the caret) to its editor" do
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

      it "derives a Date from the typed digits" do
        f = field
        type("2026-09-04")
        assert_equal Date.new(2026, 9, 4), f.value
        assert_kind_of Date, f.value
        refute f.empty?
      end

      it "does not require zero padding" do
        f = field
        type("2026-9-4")
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "reads nil for a buffer with a trailing tail no format consumes" do
        f = field
        type("2026-09-04junk")
        assert_nil f.value # Date._strptime would have ignored the tail
      end

      it "reads nil for a well-formed date the calendar does not have" do
        f = field
        type("2026-02-30")
        assert_nil f.value # _strptime yields mday: 30 quite happily
      end

      it "reads nil for leading whitespace, which strptime does not skip" do
        f = field
        type(" 2026-09-04")
        assert_nil f.value
      end

      it "fires on_value_change once per real value change" do
        f = field
        seen = []
        f.on_value_change = ->(d) { seen << d }
        type("2026-09-04")
        assert_equal [Date.new(2026, 9, 4)], seen # not once per keystroke
      end

      it "writes the primary format and parks the caret at its end" do
        f = field
        f.value = Date.new(2026, 9, 4)
        assert_equal "2026-09-04", buffer(f)
        assert_equal 10, inner(f).caret
      end

      it "empties the buffer on value = nil" do
        f = field
        f.value = Date.new(2026, 9, 4)
        f.value = nil
        assert_empty buffer(f)
        assert f.empty?
      end

      it "takes anything that answers strftime, truncating to the civil date" do
        f = field
        f.value = Time.new(2026, 9, 4, 13, 45, 0)
        assert_equal "2026-09-04", buffer(f)
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "clear empties the input, not just the value" do
        f = field
        type("garbage")
        f.clear
        assert_empty buffer(f)
        assert_nil f.value
        refute f.bad_input?
      end
    end

    describe "bad input (HasBadInput)" do
      it "reports an empty buffer as empty, not bad" do
        f = field
        assert f.empty?
        refute f.bad_input?
        assert_nil f.bad_input_message
      end

      it "reports a buffer no format parses" do
        f = field
        type("2020-13-45")
        assert_nil f.value
        assert f.empty? # empty of *value* — which is why a form asks bad_input? first
        assert f.bad_input?
        assert_equal "not a valid date", f.bad_input_message
      end

      it "reports every prefix of a date, the residue of a grammar it cannot filter" do
        f = field
        type("202")
        assert f.bad_input?
        type("6-09-04")
        refute f.bad_input?
      end
    end

    describe "no input filter at all" do
      it "admits characters no format can hold, typed" do
        f = field
        type("hello")
        assert_equal "hello", buffer(f) # unlike IntegerField, nothing is dropped
        assert f.bad_input?
      end

      it "admits a whole pasted clipboard" do
        f = field
        Screen.instance.paste("not a date")
        assert_equal "not a date", buffer(f)
        assert f.bad_input?
      end
    end

    describe "formats" do
      it "defaults to the session's locale, as a frozen Array" do
        f = field
        assert_equal ["%Y-%m-%d"], f.formats
        assert f.formats.frozen?
        assert(f.formats.all?(&:frozen?))
      end

      it "takes a single String as the one-format shorthand" do
        f = field
        f.formats = "%d.%m.%Y"
        assert_equal ["%d.%m.%Y"], f.formats
      end

      it "tries the formats in order, first whole match winning" do
        f = field
        f.formats = ["%d.%m.%Y", "%Y-%m-%d"]
        type("2026-09-04")
        assert_equal Date.new(2026, 9, 4), f.value # matched the second
        f.clear
        type("04.09.2026")
        assert_equal Date.new(2026, 9, 4), f.value # matched the first
      end

      it "writes back in the primary format whichever one parsed" do
        f = field
        f.formats = ["%d.%m.%Y", "%Y-%m-%d"]
        type("2026-09-04") # matched the second format
        blur
        assert_equal "04.09.2026", buffer(f)
      end

      it "copies the caller's list, so mutating it afterwards changes nothing" do
        f = field
        mine = ["%d.%m.%Y"]
        f.formats = mine
        mine << "%Y-%m-%d"
        assert_equal ["%d.%m.%Y"], f.formats
      end

      it "leaves a non-empty buffer alone, reparsing it under the new list" do
        f = field
        type("04.09.2026")
        assert f.bad_input?
        f.formats = "%d.%m.%Y"
        assert_equal "04.09.2026", buffer(f) # no reformat, no clear
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "fires on_value_change when the buffer now parses differently" do
        f = field
        f.formats = "%m/%d/%Y"
        type("04/09/2026")
        seen = []
        f.on_value_change = ->(d) { seen << d }
        f.formats = "%d/%m/%Y"
        assert_equal [Date.new(2026, 9, 4)], seen # April 9 was the old reading
      end

      it "raises on a list that holds no format" do
        f = field
        assert_raises(TypeError) { f.formats = :iso }
        assert_raises(TypeError) { f.formats = ["%Y-%m-%d", :iso] }
        assert_raises(ArgumentError) { f.formats = [] }
      end

      describe "the round-trip validator" do
        it "accepts the formats an app plausibly writes" do
          f = field
          ["%Y-%m-%d", "%d.%m.%Y", "%m/%d/%Y", "%Y%m%d", "%B %d, %Y", "%d-%b-%Y", "%Y-%j"].each do |format|
            f.formats = format
            assert_equal [format], f.formats
          end
        end

        it "rejects %y, naming the century it cannot carry" do
          f = field
          error = assert_raises(ArgumentError) { f.formats = "%d/%m/%y" }
          assert_includes error.message, "%y cannot carry a century"
        end

        it "rejects an incomplete format, which would silently fill in mday: 1" do
          f = field
          assert_raises(ArgumentError) { f.formats = "%Y-%m" }
        end

        it "rejects a write-only format, whose `-` flag strptime cannot read" do
          f = field
          assert_raises(ArgumentError) { f.formats = "%B %-d, %Y" }
        end

        it "rejects %D, the whole-mm/dd/yy directive that looks like a typo for %d" do
          f = field
          assert_raises(ArgumentError) { f.formats = "%Y-%m-%D" }
        end

        it "rejects %G, the ISO week-based year masquerading as %Y" do
          f = field
          assert_raises(ArgumentError) { f.formats = "%G-%m-%d" }
        end

        it "rejects %x, %X and %c, which look like a locale channel and are not" do
          f = field
          ["%x", "%X", "%c"].each do |format|
            error = assert_raises(ArgumentError) { f.formats = format }
            assert_includes error.message, "not locale-aware"
          end
        end
      end
    end

    describe "placeholder" do
      it "derives the hint from the primary format" do
        f = field
        assert_equal "yyyy-mm-dd", f.placeholder
        f.formats = "%d.%m.%Y"
        assert_equal "dd.mm.yyyy", f.placeholder
      end

      it "paints the derived hint into the empty well" do
        field
        Screen.instance.repaint
        assert_equal "yyyy-mm-dd", Screen.instance.buffer.row_text(0).strip
      end

      it "derives nothing rather than half-translating a directive it cannot spell" do
        f = field
        f.formats = "%Y-%j"
        assert_nil f.placeholder # never "yyyy-%j"
      end

      it "keeps a literal, and unescapes %%" do
        f = field
        f.formats = "%d/%m/%Y (%%)"
        assert_equal "dd/mm/yyyy (%)", f.placeholder
      end

      it "takes an override, suppresses on \"\", and restores the derived hint on nil" do
        f = field
        f.placeholder = "when it happened"
        assert_equal "when it happened", f.placeholder
        f.formats = "%d.%m.%Y" # a format change does not clobber an override
        assert_equal "when it happened", f.placeholder
        f.placeholder = ""
        assert_equal "", f.placeholder
        f.placeholder = nil
        assert_equal "dd.mm.yyyy", f.placeholder
      end

      it "refuses a placeholder that is not a String, storing nothing" do
        f = field
        assert_raises(TypeError) { f.placeholder = :hint }
        assert_equal "yyyy-mm-dd", f.placeholder
      end
    end

    describe "canonicalizing on the way out" do
      it "rewrites a loosely typed buffer in the primary format on blur" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y"]
        type("4.9.2026")
        blur
        assert_equal "2026-09-04", buffer(f)
      end

      it "leaves bad input exactly as typed" do
        f = field
        type("2020-13-45")
        blur
        assert_equal "2020-13-45", buffer(f) # the user has to see what they wrote
        assert f.bad_input?
      end

      it "fires no on_value_change, since only the spelling changed" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y"]
        type("4.9.2026")
        seen = []
        f.on_value_change = ->(d) { seen << d }
        blur
        assert_empty seen
      end

      it "canonicalizes on ENTER too, before calling on_enter" do
        f = field
        f.formats = ["%Y-%m-%d", "%d.%m.%Y"]
        seen = []
        f.on_enter = -> { seen << buffer(f) }
        type("4.9.2026")
        key(Keys::ENTER)
        assert_equal ["2026-09-04"], seen # the app's handler sees a settled buffer
      end

      it "commits on blur even when focus moved within the widget" do
        f = field
        type("2026-9-4")
        Screen.instance.focused = inner(f) # still the same widget: no commit
        assert_equal "2026-9-4", buffer(f)
        blur
        assert_equal "2026-09-04", buffer(f)
      end
    end

    describe "Up/Down" do
      it "steps a day" do
        f = field
        f.value = Date.new(2026, 9, 4)
        key(Keys::UP_ARROW)
        assert_equal Date.new(2026, 9, 5), f.value
        key(Keys::DOWN_ARROW)
        key(Keys::DOWN_ARROW)
        assert_equal Date.new(2026, 9, 3), f.value
      end

      it "steps to today from an empty field, whichever direction" do
        f = field
        key(Keys::UP_ARROW)
        assert_equal Date.today, f.value
        f.clear
        key(Keys::DOWN_ARROW)
        assert_equal Date.today, f.value
      end

      it "steps to today from bad input, dropping it" do
        f = field
        type("nonsense")
        key(Keys::UP_ARROW)
        assert_equal Date.today, f.value
        refute f.bad_input?
      end

      it "canonicalizes implicitly, since it goes through value=" do
        f = field
        type("2026-9-4")
        key(Keys::UP_ARROW)
        key(Keys::DOWN_ARROW)
        assert_equal "2026-09-04", buffer(f) # not the "2026-9-4" that was typed
      end
    end

    describe "calendar_start" do
      it "is proleptic Gregorian, not Ruby's Date::ITALY default" do
        f = field
        assert_equal Date::GREGORIAN, f.calendar_start
      end

      it "parses the ten days the Gregorian reform skipped" do
        f = field
        type("1582-10-10")
        refute_nil f.value # a Date::Error under ITALY
        refute f.bad_input?
      end

      it "rejects them again under ITALY, and fires the value change" do
        f = field
        type("1582-10-10")
        seen = []
        f.on_value_change = ->(d) { seen << d }
        f.calendar_start = Date::ITALY
        assert_nil f.value
        assert f.bad_input?
        assert_equal [nil], seen
        assert_equal "1582-10-10", buffer(f) # the buffer itself is left alone
      end

      it "reads a pre-1582 date nine days off an ITALY one, as documented" do
        f = field
        type("1500-01-01")
        assert_equal Date.new(1500, 1, 1, Date::GREGORIAN), f.value
        refute_equal Date.new(1500, 1, 1), f.value # app code's default is ITALY
      end

      it "refuses a start that is not a Julian Day Number" do
        f = field
        assert_raises(TypeError) { f.calendar_start = :gregorian }
      end
    end

    describe "following the session's locale" do
      it "takes both conventions from the screen when neither is set" do
        Screen.instance.locale = Locale::ISO.with(date_formats: ["%d.%m.%Y"], calendar_start: Date::ITALY)
        f = Component::DateField.new
        assert_equal ["%d.%m.%Y"], f.formats
        assert_equal Date::ITALY, f.calendar_start
        assert_equal "dd.mm.yyyy", f.placeholder
      end

      it "reaches a field built before the locale changed, hint and all" do
        f = field
        assert_equal "yyyy-mm-dd", f.placeholder
        Screen.instance.locale = Locale::ISO.with(date_formats: ["%d.%m.%Y"])
        assert_equal ["%d.%m.%Y"], f.formats
        assert_equal "dd.mm.yyyy", f.placeholder
      end

      it "rewrites a buffer that still parses into the new primary format" do
        f = field
        f.value = Date.new(2026, 9, 4)
        Screen.instance.locale = Locale::ISO.with(date_formats: ["%d.%m.%Y", "%Y-%m-%d"])
        assert_equal "04.09.2026", inner(f).text
        assert_equal Date.new(2026, 9, 4), f.value
      end

      it "leaves a buffer the new grammar cannot parse as typed, and reports it bad" do
        f = field
        changes = []
        f.value = Date.new(2026, 9, 4)
        f.on_value_change = ->(v) { changes << v }
        Screen.instance.locale = Locale::ISO.with(date_formats: ["%d.%m.%Y"])
        assert_equal "2026-09-04", inner(f).text
        assert_nil f.value
        assert f.bad_input?
        assert_equal [nil], changes
      end

      it "leaves a field alone that overrode both conventions itself" do
        f = field
        f.formats = "%Y-%m-%d"
        f.calendar_start = Date::GREGORIAN
        f.value = Date.new(2026, 9, 4)
        Screen.instance.locale = Locale::ISO.with(date_formats: ["%d.%m.%Y"], calendar_start: Date::ITALY)
        assert_equal ["%Y-%m-%d"], f.formats
        assert_equal "2026-09-04", inner(f).text
      end

      it "follows the locale again once an override is cleared" do
        f = field
        f.formats = "%d.%m.%Y"
        f.calendar_start = Date::ITALY
        f.formats = nil
        f.calendar_start = nil
        assert_equal Locale::ISO.date_formats, f.formats
        assert_equal Locale::ISO.calendar_start, f.calendar_start
        assert_equal "yyyy-mm-dd", f.placeholder
      end

      it "answers ISO with no screen in the process at all" do
        Screen.close
        f = Component::DateField.new
        assert_equal Locale::ISO.date_formats, f.formats
        assert_equal Locale::ISO.calendar_start, f.calendar_start
      end
    end

    describe "the background well settles" do
      def well = Screen.instance.buffer.cell(0, 0).style.bg
      # Either error shade counts as red: a *focused* invalid field still has to
      # look focused, so the well is error_active_bg_color until it is blurred.

      def red?
        theme = Screen.instance.theme
        [theme.error_bg_color, theme.error_active_bg_color].include?(well)
      end

      def repaint = Screen.instance.repaint

      it "stays quiet while a correct date is being typed" do
        f = field
        "2026-09-04".each_char do |ch|
          Screen.instance.send(:handle_key, ch)
          repaint
          refute red?, "reddened at #{buffer(f).inspect}, mid-typing"
        end
      end

      it "reddens what did not parse once the field is left" do
        field
        type("2020-13-45")
        repaint
        refute red? # not while they are still typing
        blur
        repaint
        assert red?
      end

      it "reddens on ENTER too, which moves no focus" do
        f = field
        type("2020-13-45")
        key(Keys::ENTER)
        repaint
        assert red?
        assert f.bad_input? # …and the report itself never waited
      end

      it "goes quiet again on the next edit, and comes back on the next commit" do
        field
        type("2020-13-45")
        blur
        repaint
        assert red?
        Screen.instance.focused = Testing.get(Component::DateField)
        key(Keys::BACKSPACE)
        repaint
        refute red? # the user is having another go
        blur
        repaint
        assert red?
      end

      it "leaves a parseable buffer alone through both gestures" do
        field
        type("2026-09-04")
        key(Keys::ENTER)
        blur
        repaint
        refute red?
      end

      it "reports bad input immediately whatever the well is doing" do
        f = field
        type("2")
        assert f.bad_input?, "the pull a save gate uses must not wait for a commit"
        assert_equal "not a valid date", f.bad_input_message
      end
    end
  end
end
