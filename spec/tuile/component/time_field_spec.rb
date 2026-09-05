# frozen_string_literal: true

module Tuile
  describe Component::TimeField do
    before { Screen.fake }
    # Nothing to restore: the conventions live on the screen, which the next
    # `Screen.fake` replaces. {FakeScreen} pins them to {Locale::ISO}.
    after { Screen.close }

    # Attaches a time field as the tiled content, sizes it to a single 20-wide
    # row, and focuses it (so key dispatch reaches its inner editor).
    def field(width: 20)
      f = Component::TimeField.new
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
    def at(hour, minute, second = 0) = Component::TimeField.time_of_day(hour, minute, second)

    # A spelling that is neither ISO's nor American, so an assertion can tell
    # "kept the locale's spelling" from "happened to match ISO".
    def finnish = Locale::ISO.with(time_formats: ["%H.%M.%S", "%H:%M:%S"])

    it "is a focusable non-tab-stop wrapper of a single editor" do
      f = field
      assert f.focusable?
      refute f.tab_stop? # the inner editor carries the tab stop, not the wrapper
      assert_equal [inner(f)], f.children
    end

    describe "#value" do
      it "is nil and empty? on a blank buffer" do
        f = field
        assert_nil f.value
        assert f.empty?
      end

      it "derives a Time on the epoch from the typed digits" do
        f = field
        type("13:45")
        assert_equal at(13, 45), f.value
        assert_equal Component::TimeField::MIDNIGHT.to_date, f.value.to_date
        assert f.value.utc?
      end

      it "does not require zero padding" do
        f = field
        type("1:45")
        assert_equal at(1, 45), f.value
      end

      it "reads nil for a buffer with a tail no format consumes" do
        f = field
        type("13:45junk")
        assert_nil f.value
      end

      it "rejects 24:00, which Time would silently roll into the next day" do
        f = field
        type("24:00")
        assert_nil f.value
        assert f.bad_input?
      end

      it "rejects a 60th second, which Time would roll into the next minute" do
        f = field
        f.step = 1
        type("13:45:60")
        assert_nil f.value
        assert f.bad_input?
      end

      it "reads a half-typed 13:4 as 13:04, since padding is optional" do
        f = field
        type("13:4")
        assert_equal at(13, 4), f.value # a real intermediate, not bad input
        refute f.bad_input?
      end

      it "fires on_value_change once per real value change" do
        f = field
        seen = []
        f.on_value_change = ->(t) { seen << t }
        f.value = at(13, 45)
        f.value = at(13, 45) # same value, rewritten — silent
        f.value = at(9, 30)
        assert_equal [at(13, 45), at(9, 30)], seen
      end
    end

    describe "#value=" do
      it "writes the primary format and parks the caret at its end" do
        f = field
        f.value = at(13, 45)
        assert_equal "13:45", buffer(f)
        assert_equal 5, inner(f).caret
      end

      it "empties the buffer on value = nil" do
        f = field
        f.value = at(13, 45)
        f.value = nil
        assert_equal "", buffer(f)
        assert f.empty?
      end

      it "takes anything answering hour/min/sec, dropping the date and zone" do
        f = field
        f.step = 1
        f.value = DateTime.new(2026, 9, 4, 13, 45, 30)
        assert_equal "13:45:30", buffer(f)
        # The Sequel::SQLTime shape, without the gem: a duck type is all it takes.
        f.value = Data.define(:hour, :min, :sec).new(hour: 9, min: 30, sec: 15)
        assert_equal "09:30:15", buffer(f)
      end

      it "truncates a fraction of a second, which a time of day does not hold" do
        f = field
        f.step = 1
        f.value = Time.utc(2026, 9, 4, 13, 45, 30, 500_000)
        assert_equal "13:45:30", buffer(f)
      end

      it "refuses a Date, which has no hour to take" do
        f = field
        assert_raises(TypeError) { f.value = Date.new(2026, 9, 4) }
      end

      it "refuses a String, which is what the buffer is for" do
        f = field
        assert_raises(TypeError) { f.value = "13:45" }
      end

      it "clear empties the input, not just the value" do
        f = field
        type("nonsense")
        f.clear
        assert_equal "", buffer(f)
        refute f.bad_input?
      end
    end

    describe ".time_of_day" do
      it "builds a value on the epoch, in UTC — not a field" do
        assert_equal Time.utc(2000, 1, 1, 13, 45, 0), at(13, 45)
        assert_equal Time.utc(2000, 1, 1, 9, 30, 15), at(9, 30, 15)
      end

      it "shares the parse's range gate, so it cannot build the next day" do
        assert_raises(ArgumentError) { at(24, 0) }
        assert_raises(ArgumentError) { at(13, 60) }
        assert_raises(ArgumentError) { at(13, 45, 60) }
        assert_raises(ArgumentError) { at(-1, 0) }
      end
    end

    describe "#set_to" do
      it "sets the value from its parts, so no caller assembles an epoch Time" do
        f = field
        f.set_to(13, 45)
        assert_equal "13:45", buffer(f)
        assert_equal at(13, 45), f.value
      end

      it "keeps the seconds only where the stride shows them" do
        f = field
        f.set_to(9, 30, 15)
        assert_equal "09:30", buffer(f) # the buffer is the truth: they are gone
        f.step = 1
        f.set_to(9, 30, 15)
        assert_equal "09:30:15", buffer(f)
      end

      it "shares the same range gate" do
        f = field
        assert_raises(ArgumentError) { f.set_to(24, 0) }
        assert_raises(ArgumentError) { f.set_to(13, 45, 60) }
      end

      it "fires on_value_change, being an ordinary write" do
        f = field
        seen = []
        f.on_value_change = ->(t) { seen << t }
        f.set_to(13, 45)
        assert_equal [at(13, 45)], seen
      end
    end

    describe "#set_to_now" do
      it "lands on the wall clock, truncated to the field's precision" do
        f = field
        f.set_to_now
        wall = Time.now
        assert_equal at(wall.hour, wall.min), f.value
        assert_equal 0, f.value.sec
      end

      it "keeps the seconds under a minute stride" do
        f = field
        f.step = 1
        f.set_to_now
        assert_equal Time.now.hour, f.value.hour
        assert_match(/\A\d\d:\d\d:\d\d\z/, buffer(f))
      end

      it "is where Up/Down land an empty field" do
        f = field
        key(Keys::UP_ARROW)
        stepped = f.value
        f.clear
        f.set_to_now
        assert_equal stepped, f.value
      end
    end

    describe "#step" do
      it "defaults to a minute, and hides seconds there" do
        f = field
        assert_equal 60, f.step
        assert_equal ["%H:%M"], f.formats
      end

      it "shows seconds under a minute, with the seconds forms first" do
        f = field
        f.step = 1
        assert_equal ["%H:%M:%S", "%H:%M"], f.formats
      end

      it "lets a minute-precision buffer widen losslessly, since the list is lenient" do
        f = field
        f.step = 1
        type("13:45")
        assert_equal at(13, 45), f.value
        blur
        assert_equal "13:45:00", buffer(f)
      end

      it "keeps seconds bad input at a minute stride, the lossy direction" do
        f = field
        type("13:45:30")
        assert_nil f.value
        assert f.bad_input?
      end

      it "refuses a stride that is not a whole number of seconds" do
        f = field
        assert_raises(TypeError) { f.step = 1.5 }
        assert_raises(TypeError) { f.step = nil }
        assert_equal 60, f.step
      end

      it "refuses a stride outside a day" do
        f = field
        assert_raises(ArgumentError) { f.step = 0 }
        assert_raises(ArgumentError) { f.step = -1 }
        assert_raises(ArgumentError) { f.step = 86_400 }
        assert_equal 60, f.step
      end

      it "takes a stride that divides no hour, unlike Vaadin's" do
        f = field
        f.step = 7
        assert_equal 7, f.step
        f.step = 90
        assert_equal 90, f.step
      end
    end

    describe "#step= over a buffer" do
      it "widens a buffer that still parses into the new primary" do
        f = field
        seen = []
        f.value = at(13, 45)
        f.on_value_change = ->(t) { seen << t }
        f.step = 1
        assert_equal "13:45:00", buffer(f)
        assert_empty seen # the spelling changed, not the value
      end

      it "narrows a buffer whose seconds are zero, since that discards nothing" do
        f = field
        f.step = 1
        f.value = at(13, 45)
        assert_equal "13:45:00", buffer(f)
        f.step = 60
        assert_equal "13:45", buffer(f)
        assert_equal at(13, 45), f.value
        refute f.bad_input?
      end

      it "leaves a buffer with real seconds as typed, and reports it bad" do
        f = field
        seen = []
        f.step = 1
        type("13:45:30")
        f.on_value_change = ->(t) { seen << t }
        f.step = 60
        assert_equal "13:45:30", buffer(f) # never silently truncated
        assert_nil f.value
        assert f.bad_input?
        assert_equal [nil], seen
      end
    end

    describe "#formats" do
      it "is a report with no writer" do
        refute_respond_to field, :formats=
      end

      it "reduces the locale's spelling to the field's precision, keeping the spelling" do
        f = field
        Screen.instance.locale = finnish
        assert_equal ["%H.%M", "%H:%M"], f.formats
        f.step = 1
        assert_equal ["%H.%M.%S", "%H:%M:%S", "%H.%M", "%H:%M"], f.formats
      end

      it "reduces an American spelling the same way" do
        f = field
        Screen.instance.locale = Locale::ISO.with(time_formats: ["%I:%M:%S %p", "%H:%M:%S"])
        assert_equal ["%I:%M %p", "%H:%M"], f.formats
        f.step = 1
        assert_equal ["%I:%M:%S %p", "%H:%M:%S", "%I:%M %p", "%H:%M"], f.formats
      end

      it "falls back to ISO seconds when the locale's own spelling stops at minutes" do
        f = field
        Screen.instance.locale = Locale::ISO.with(time_formats: ["%H:%M"])
        assert_equal ["%H:%M"], f.formats
        f.step = 1
        assert_equal ["%H:%M:%S", "%H:%M"], f.formats
      end

      it "follows a locale reassignment rather than snapshotting one" do
        f = field
        assert_equal ["%H:%M"], f.formats
        Screen.instance.locale = finnish
        assert_equal ["%H.%M", "%H:%M"], f.formats
      end

      it "is frozen, so nothing can push onto the list in force" do
        assert field.formats.frozen?
      end

      it "answers ISO with no screen in the process at all" do
        Screen.close
        f = Component::TimeField.new
        assert_equal ["%H:%M"], f.formats
        assert_equal "hh:mm", f.placeholder
      end
    end

    describe "the placeholder" do
      it "derives the hint from the primary format" do
        f = field
        assert_equal "hh:mm", f.placeholder
        f.step = 1
        assert_equal "hh:mm:ss", f.placeholder
      end

      it "keeps the locale's spelling in the hint" do
        f = field
        Screen.instance.locale = finnish
        assert_equal "hh.mm", f.placeholder
        Screen.instance.locale = Locale::ISO.with(time_formats: ["%I:%M:%S %p"])
        assert_equal "hh:mm AM", f.placeholder
      end

      it "paints the derived hint into the empty well" do
        field
        Screen.instance.repaint
        assert_match(/hh:mm/, Screen.instance.buffer.row_text(0))
      end

      it "takes an override, suppresses on \"\", and restores the derived hint on nil" do
        f = field
        f.placeholder = "when it happened"
        assert_equal "when it happened", f.placeholder
        f.placeholder = ""
        assert_equal "", f.placeholder
        f.placeholder = nil
        assert_equal "hh:mm", f.placeholder
      end
    end

    describe "committing" do
      it "rewrites a loosely typed buffer in the primary format on blur" do
        f = field
        type("1:45")
        blur
        assert_equal "01:45", buffer(f)
      end

      it "leaves bad input exactly as typed" do
        f = field
        type("half past one")
        blur
        assert_equal "half past one", buffer(f)
      end

      it "canonicalizes on ENTER too, which moves no focus" do
        f = field
        type("1:45")
        key(Keys::ENTER)
        assert_equal "01:45", buffer(f)
      end

      it "accepts every spelling of %p Ruby's strptime does" do
        f = field
        Screen.instance.locale = Locale::ISO.with(time_formats: ["%I:%M:%S %p"])
        ["1:45pm", "1:45 PM", "1:45PM", "1:45 pm"].each do |typed|
          inner(f).text = typed
          assert_equal at(13, 45), f.value, typed
        end
      end
    end

    describe "stepping" do
      it "steps by the stride, both directions" do
        f = field
        f.value = at(13, 45)
        key(Keys::UP_ARROW)
        assert_equal "13:46", buffer(f)
        key(Keys::DOWN_ARROW)
        assert_equal "13:45", buffer(f)
      end

      it "wraps at midnight, since a clock has no day to carry into" do
        f = field
        f.value = at(23, 59)
        key(Keys::UP_ARROW)
        assert_equal "00:00", buffer(f)
        key(Keys::DOWN_ARROW)
        assert_equal "23:59", buffer(f)
      end

      it "adds rather than snapping to a grid" do
        f = field
        f.step = 900
        f.value = at(13, 7)
        key(Keys::UP_ARROW)
        assert_equal "13:22", buffer(f) # not 13:15
      end

      it "carries seconds when the stride shows them" do
        f = field
        f.step = 1
        f.value = at(13, 45, 30)
        key(Keys::UP_ARROW)
        assert_equal "13:45:31", buffer(f)
      end

      it "steps to now from an empty field, whichever direction" do
        f = field
        key(Keys::UP_ARROW)
        wall = Time.now
        assert_equal at(wall.hour, wall.min), f.value
      end

      it "zeroes the seconds of now at a minute stride, and keeps them under one" do
        f = field
        key(Keys::UP_ARROW)
        assert_equal 0, f.value.sec
        f.clear
        f.step = 1
        key(Keys::UP_ARROW)
        assert_equal Time.now.hour, f.value.hour
      end

      it "steps to now from bad input, dropping it" do
        f = field
        type("nonsense")
        key(Keys::UP_ARROW)
        refute f.bad_input?
        assert_equal Time.now.hour, f.value.hour
      end

      it "steps an hour on PageUp/PageDown, keeping the minutes" do
        f = field
        f.value = at(13, 45)
        key(Keys::PAGE_UP)
        assert_equal "14:45", buffer(f)
        key(Keys::PAGE_DOWN)
        assert_equal "13:45", buffer(f)
      end

      it "steps an hour whatever the stride, and wraps it at midnight too" do
        f = field
        f.step = 1
        f.value = at(23, 45, 30)
        key(Keys::PAGE_UP)
        assert_equal "00:45:30", buffer(f)
      end

      it "steps to now from an empty field on PageDown as well" do
        f = field
        key(Keys::PAGE_DOWN)
        assert_equal Time.now.hour, f.value.hour
      end

      it "consumes PageUp/PageDown, so a scope root binding them never sees them" do
        f = Component::TimeField.new
        seen = []
        Screen.instance.content = Component::Layout::Absolute.new.tap do |root|
          root.add(f)
          root.define_singleton_method(:handle_key) { |k| seen << k }
        end
        f.rect = Rect.new(0, 0, 20, 1)
        Screen.instance.focused = f
        f.value = at(13, 45)
        key(Keys::PAGE_UP)
        key(Keys::PAGE_UP)
        key(Keys::PAGE_DOWN)
        assert_empty seen
        assert_equal "14:45", buffer(f) # …and were acted on
      end
    end

    describe "bad input is reported, not filtered" do
      it "reports an empty buffer as empty, not bad" do
        f = field
        assert f.empty?
        refute f.bad_input?
        assert_nil f.bad_input_message
      end

      it "reports a buffer no format parses" do
        f = field
        type("13:99")
        assert f.bad_input?
        assert_equal "not a valid time", f.bad_input_message
      end

      it "reports every prefix of a time, the residue of a grammar it cannot filter" do
        f = field
        # "13:4" is deliberately absent: unpadded minutes parse, so it is 13:04.
        ["1", "13", "13:"].each do |prefix|
          inner(f).text = prefix
          assert f.bad_input?, prefix
        end
        inner(f).text = "13:45"
        refute f.bad_input?
      end

      it "admits characters no format can hold, typed" do
        f = field
        type("abc")
        assert_equal "abc", buffer(f)
      end

      it "admits a whole pasted clipboard" do
        f = field
        inner(f).handle_paste("not a time at all")
        assert_equal "not a time at all", buffer(f)
        assert f.bad_input?
      end
    end

    describe "the background well settles" do
      def well = Screen.instance.buffer.cell(0, 0).style.bg

      def red?
        theme = Screen.instance.theme
        [theme.error_bg_color, theme.error_active_bg_color].include?(well)
      end

      def repaint = Screen.instance.repaint

      it "stays quiet while a correct time is being typed" do
        f = field
        %w[1 3 : 4 5].each do |ch|
          type(ch)
          repaint
          refute red?, "reddened at #{buffer(f).inspect}"
        end
      end

      it "reddens what did not parse once the field is left" do
        field
        type("13:99")
        repaint
        refute red?
        blur
        repaint
        assert red?
      end

      it "goes quiet again on the next edit" do
        f = field
        type("13:99")
        key(Keys::ENTER)
        repaint
        assert red?
        Screen.instance.focused = f
        type("9")
        repaint
        refute red?
      end

      it "reports bad input immediately whatever the well is doing" do
        f = field
        type("13:99")
        assert f.bad_input? # the pull never waits for the latch
        repaint
        refute red?
      end
    end

    describe "the session's locale" do
      it "reaches a field built before the locale changed, hint and all" do
        f = field
        Screen.instance.locale = finnish
        assert_equal "hh.mm", f.placeholder
      end

      it "rewrites a buffer that still parses into the new spelling" do
        f = field
        f.value = at(13, 45)
        Screen.instance.locale = finnish
        assert_equal "13.45", buffer(f)
        assert_equal at(13, 45), f.value
      end

      it "leaves a buffer the new grammar cannot parse as typed, and reports it bad" do
        f = field
        seen = []
        f.value = at(13, 45) # "13:45" under ISO
        f.on_value_change = ->(t) { seen << t }
        Screen.instance.locale = Locale::ISO.with(time_formats: ["%Hh%M:%S"])
        assert_equal "13:45", buffer(f) # left exactly as typed
        assert f.bad_input?
        assert_equal [nil], seen
      end
    end
  end
end
