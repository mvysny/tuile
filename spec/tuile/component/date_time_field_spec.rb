# frozen_string_literal: true

module Tuile
  describe Component::DateTimeField do
    before { Screen.fake }
    # Nothing to restore: the conventions live on the screen, which the next
    # `Screen.fake` replaces. {FakeScreen} pins them to {Locale::ISO}.
    after { Screen.close }

    # Attaches a field as the tiled content, sizes it to a single 20-wide row
    # (the date half takes columns 0..12, the gap 13, the time half 14..19) and
    # focuses it, so key dispatch reaches the date half's editor.
    def field(width: 20)
      f = Component::DateTimeField.new
      mount_at(f, Rect.new(0, 0, width, 1))
      Screen.instance.focused = f
      f
    end

    # The halves' editors are private by design; Testing.get is the way in.
    def editor(half) = Testing.get(Component::TextField, in: half)
    def buffer(half) = editor(half).text
    def focus(half) = (Screen.instance.focused = editor(half))
    # Screen#handle_key? is the (private) key-dispatch entry the event loop
    # drives; poke it directly to simulate typing without a real loop.
    def type(str) = str.each_char { |ch| Screen.instance.send(:handle_key?, ch) }
    def key(code) = Screen.instance.send(:handle_key?, code)
    # Blur: dropping focus takes the whole field off the focus chain.
    def blur = (Screen.instance.focused = nil)

    def moment = DateTime.new(2026, 9, 14, 13, 45)

    it "is a focusable non-tab-stop pair of fields" do
      f = field
      assert f.focusable?
      refute f.tab_stop? # the two stops inside it are the two editors
      assert_equal [f.date_field, f.time_field], f.children
    end

    it "forwards focus into the date half" do
      f = field
      assert_same editor(f.date_field), Screen.instance.focused
      assert f.active? # …and the composite is on the chain, which the ink rule reads
    end

    it "lays the halves out 2:1 around a one-column gap" do
      f = field(width: 16) # the natural minimum: 10 columns of date, 5 of time
      assert_equal Rect.new(0, 0, 10, 1), f.date_field.rect
      assert_equal Rect.new(11, 0, 5, 1), f.time_field.rect
    end

    describe "value" do
      it "is nil and empty? while both halves are" do
        f = field
        assert_nil f.value
        assert f.empty?
      end

      it "assembles a DateTime once both halves parse" do
        f = field
        type("2026-09-14")
        focus(f.time_field)
        type("13:45")
        assert_equal moment, f.value
        assert_kind_of DateTime, f.value
        refute f.empty?
      end

      it "is nil while only one half parses" do
        f = field
        type("2026-09-14")
        assert_nil f.value
      end

      it "writes both halves, in the primary format of each" do
        f = field
        f.value = moment
        assert_equal "2026-09-14", buffer(f.date_field)
        assert_equal "13:45", buffer(f.time_field)
      end

      it "carries the date half's calendar into the result" do
        f = field
        f.date_field.calendar_start = Date::ITALY
        f.value = moment
        assert_equal Date::ITALY, f.value.start
      end

      it "takes anything carrying both a date and a time of day" do
        f = field
        f.value = Time.utc(2026, 9, 14, 13, 45)
        assert_equal moment, f.value
      end

      it "hands back +00:00, so a zoned input does not round-trip" do
        f = field
        f.value = DateTime.new(2026, 9, 14, 13, 45, 0, "+03:00")
        assert_equal moment, f.value # the wall clock, at the placeholder offset
      end

      it "refuses a Date, before either half is written" do
        f = field
        f.value = moment
        assert_raises(TypeError) { f.value = Date.new(2027, 1, 2) }
        assert_equal moment, f.value # …so a rejected value leaves the field as it was
      end

      it "empties both halves on nil" do
        f = field
        f.value = moment
        f.value = nil
        assert_equal ["", ""], [buffer(f.date_field), buffer(f.time_field)]
      end

      it "clears the input of both halves, not just the value" do
        f = field
        type("2020-99-99")
        focus(f.time_field)
        type("13:45")
        f.clear
        assert_equal ["", ""], [buffer(f.date_field), buffer(f.time_field)]
        assert f.empty?
      end
    end

    describe "the value notice" do
      def fired(fld)
        seen = []
        fld.on_value_change { |e| seen << e.value }
        seen
      end

      it "announces a value= once, never half-assembled" do
        f = field
        f.value = moment
        seen = fired(f)
        f.value = DateTime.new(2027, 1, 2, 8, 30)
        assert_equal [DateTime.new(2027, 1, 2, 8, 30)], seen
      end

      it "announces a clear once" do
        f = field
        f.value = moment
        seen = fired(f)
        f.clear
        assert_equal [nil], seen
      end

      it "waits for the half's commit rather than firing per keystroke" do
        f = field
        f.value = moment
        seen = fired(f)
        key(Keys::BACKSPACE) # the date buffer now reads 2026-09-1
        assert_empty seen, "announced a half-typed date"
        blur
        assert_equal [DateTime.new(2026, 9, 1, 13, 45)], seen
      end

      it "says nothing when a commit leaves the value alone" do
        f = field
        f.value = moment
        seen = fired(f)
        key(Keys::ENTER)
        blur
        assert_empty seen
      end

      it "announces an Up/Down step as it happens" do
        f = field
        f.value = moment
        seen = fired(f)
        key(Keys::UP_ARROW)
        assert_equal [DateTime.new(2026, 9, 15, 13, 45)], seen
      end
    end

    describe "bad input" do
      it "reports nothing while both halves are empty" do
        f = field
        refute f.bad_input?
        assert_nil f.bad_input_message
      end

      it "reports the guilty half's own message" do
        f = field
        type("2026-99-99")
        focus(f.time_field)
        type("13:45")
        assert_equal "not a valid date", f.bad_input_message
      end

      it "reports the date half first when both are bad" do
        f = field
        type("2026-99-99")
        focus(f.time_field)
        type("99:99")
        assert_equal "not a valid date", f.bad_input_message
      end

      it "reports a half-filled pair as its own fault" do
        f = field
        type("2026-09-14")
        assert_equal "needs both a date and a time", f.bad_input_message
        assert f.bad_input?
        assert f.empty? # empty of *value*, which is why a form asks bad_input? first
      end

      it "reports nothing once both halves parse" do
        f = field
        f.value = moment
        refute f.bad_input?
      end
    end

    describe "the report is relayed, latch and all" do
      def fired(fld)
        seen = []
        fld.on_bad_input_change { |e| seen << e.message }
        seen
      end

      it "announces the guilty half's message when that half settles" do
        f = field
        seen = fired(f)
        type("2026-99-99")
        assert_empty seen, "the half has not settled, so neither has the relay"
        focus(f.time_field) # commits the date half, without leaving this field
        assert_equal ["not a valid date"], seen
        assert f.active?, "the words arrive while the user is still in the pair"
      end

      it "settles the half-filled fault on leaving the field" do
        f = field
        seen = fired(f)
        type("2026-09-14")
        assert_empty seen
        blur
        assert_equal ["needs both a date and a time"], seen
      end

      it "takes it back once the pair is completed" do
        f = field
        type("2026-09-14")
        blur
        seen = fired(f)
        focus(f.time_field)
        type("13:45")
        blur
        assert_equal [nil], seen
      end

      it "does not announce the half-assembled state while both halves are written" do
        f = field
        f.value = moment
        blur
        seen = fired(f)
        f.clear # passes through a date with no time, which the user was never in
        assert_empty seen
      end
    end

    describe "the ink" do
      # Either error shade counts as red: a focused invalid field still has to
      # look focused, so the well is error_active_bg_color until it is blurred.
      def red?(column)
        theme = Screen.instance.theme
        Screen.instance.repaint
        [theme.error_bg_color, theme.error_active_bg_color].include?(
          Screen.instance.buffer.cell(column, 0).style.bg
        )
      end

      def date_red?(fld) = red?(fld.date_field.rect.left)
      def time_red?(fld) = red?(fld.time_field.rect.left)

      it "leaves an attributable fault to the half that wears it" do
        f = field
        type("2026-99-99")
        focus(f.time_field)
        type("13:45")
        blur
        assert date_red?(f), "the guilty half did not redden itself"
        refute time_red?(f), "the innocent half reddened"
      end

      it "reddens whole for a half-filled pair, but only once you leave" do
        f = field
        type("2026-09-14")
        refute date_red?(f), "judged the user mid-edit"
        refute time_red?(f)
        blur
        assert date_red?(f)
        assert time_red?(f)
      end

      it "stays quiet on ENTER, which moves no focus" do
        f = field
        type("2026-09-14")
        key(Keys::ENTER)
        refute date_red?(f)
        assert f.bad_input?, "…while the report itself never waited"
      end

      it "goes quiet again when you come back to fix it" do
        f = field
        type("2026-09-14")
        blur
        assert date_red?(f)
        focus(f.time_field)
        refute date_red?(f)
        refute time_red?(f)
      end

      it "reddens whole for a validator's verdict, with no latch at all" do
        f = field
        f.value = moment
        f.error_message = "must be in the future"
        assert date_red?(f)
        assert time_red?(f)
      end

      it "gives the halves their own wells back when the verdict clears" do
        f = field
        f.value = moment
        f.error_message = "nope"
        assert_equal [ComponentBackground::INHERIT] * 2, [f.date_field.bg_color, f.time_field.bg_color]
        f.error_message = nil
        assert_equal [nil, nil], [f.date_field.bg_color, f.time_field.bg_color]
        refute date_red?(f)
      end

      it "leaves the gap between the halves out of its own well" do
        f = field
        f.value = moment
        f.error_message = "nope"
        blur
        refute red?(f.time_field.rect.left - 1), "the spacing column stopped reading as a gap"
      end
    end

    describe "the surface" do
      def row(index) = Screen.instance.buffer.region_text(Rect.new(0, index, 20, 1)).first

      it "paints one row whatever height it is given" do
        f = field
        Testing.place(f, Rect.new(0, 0, 20, 4))
        f.value = moment
        Screen.instance.repaint
        assert_equal "2026-09-14    13:45 ", row(0)
        assert_equal " " * 20, row(1)
        assert_nil Screen.instance.buffer.cell(0, 1).style.bg, "the well flooded the dead tail"
      end

      # The blanking itself is `Component#repaint`'s (see component_spec); what
      # this pins is that the field does not decline it.
      it "blanks the span of a hidden half" do
        f = field
        f.value = moment
        Screen.instance.repaint
        f.time_field.visible = false
        Screen.instance.repaint
        assert_equal "2026-09-14          ", row(0)
      end
    end

    describe "the halves are readers" do
      it "re-spells the date half without a forwarder of its own" do
        f = field
        f.date_field.formats = "%d.%m.%Y"
        f.value = moment
        assert_equal "14.09.2026", buffer(f.date_field)
        assert_equal moment, f.value
      end

      it "takes the time half's step and precision the same way" do
        f = field
        f.time_field.step = 1
        f.value = DateTime.new(2026, 9, 14, 13, 45, 30)
        assert_equal "13:45:30", buffer(f.time_field)
        assert_equal DateTime.new(2026, 9, 14, 13, 45, 30), f.value
      end
    end
  end
end
