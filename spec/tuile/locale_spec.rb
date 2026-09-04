# frozen_string_literal: true

module Tuile
  describe Locale do
    # One `locale -k` answer, as glibc actually prints it: strings quoted,
    # numbers bare, lists semicolon-separated.
    def keywords(**overrides)
      {
        "d_fmt" => "%d.%m.%Y",
        "first_weekday" => "2",
        "mon" => (1..12).map { "M#{_1}" }.join(";"),
        "abmon" => (1..12).map { "m#{_1}" }.join(";"),
        "day" => %w[So Mo Di Mi Do Fr Sa].join(";"),
        "abday" => %w[So Mo Di Mi Do Fr Sa].join(";"),
        "decimal_point" => ","
      }.merge(overrides.transform_keys(&:to_s))
    end

    def spoken(name = "de_DE.UTF-8") = { "LC_ALL" => name }

    describe "ISO, the floor" do
      it "cites one standard three times over" do
        assert_equal ["%Y-%m-%d"], Locale::ISO.date_formats
        assert_equal Date::GREGORIAN, Locale::ISO.calendar_start # proleptic, as ISO 8601 mandates
        assert_equal 1, Locale::ISO.first_weekday # Monday, in Date#wday numbering
      end

      it "borrows Ruby's English tables rather than authoring any" do
        assert_equal "September", Locale::ISO.month_names[9]
        assert_equal "Sep", Locale::ISO.abbr_month_names[9]
        assert_equal "Sunday", Locale::ISO.day_names[0]
        assert_equal "Mon", Locale::ISO.abbr_day_names[1]
      end

      it "separates decimals the way Float#to_s does, since value= goes through it" do
        assert_equal ".", Locale::ISO.decimal_separator
      end

      it "is frozen all the way down" do
        assert Locale::ISO.frozen?
        assert Locale::ISO.date_formats.frozen?
        assert Locale::ISO.month_names.frozen?
        assert Locale::ISO.day_names.frozen?
      end
    end

    describe "the name tables are keyed by the Date accessor that reads them" do
      it "keys months 1..12, so Date#month indexes them directly" do
        assert_equal "September", Locale::ISO.month_names[Date.new(2026, 9, 4).month]
      end

      it "indexes days 0..6, so Date#wday does" do
        assert_equal "Friday", Locale::ISO.day_names[Date.new(2026, 9, 4).wday]
      end

      it "refuses an Array of months — the off-by-one this keying exists to prevent" do
        error = assert_raises(TypeError) { Locale::ISO.with(month_names: Date::MONTHNAMES[1..]) }
        assert_includes error.message, "Hash keyed 1..12"
      end

      it "refuses a Hash of days, and a month table keyed from zero" do
        assert_raises(TypeError) { Locale::ISO.with(day_names: (0..6).zip(Date::DAYNAMES).to_h) }
        assert_raises(ArgumentError) { Locale::ISO.with(month_names: (0..11).zip(Date::MONTHNAMES[1..]).to_h) }
      end
    end

    describe "validation, which #with re-runs" do
      it "rejects a member Data#with would otherwise smuggle past the constructor" do
        assert_raises(ArgumentError) { Locale::ISO.with(date_formats: ["%d/%m/%y"]) }
        assert_raises(ArgumentError) { Locale::ISO.with(first_weekday: 7) }
        assert_raises(ArgumentError) { Locale::ISO.with(day_names: %w[a b c]) }
        assert_raises(TypeError) { Locale::ISO.with(calendar_start: :gregorian) }
      end

      it "holds the decimal separator to the one-cluster, one-column glyph rule" do
        assert_equal ",", Locale::ISO.with(decimal_separator: ",").decimal_separator
        assert_raises(ArgumentError) { Locale::ISO.with(decimal_separator: ",,") }
        assert_raises(ArgumentError) { Locale::ISO.with(decimal_separator: "") }
        assert_raises(ArgumentError) { Locale::ISO.with(decimal_separator: "，") } # fullwidth: 2 columns
      end

      it "freezes what it is handed, so a caller's array cannot change it afterwards" do
        mine = ["%d.%m.%Y"]
        locale = Locale::ISO.with(date_formats: mine)
        mine << "%Y-%m-%d"
        assert_equal ["%d.%m.%Y"], locale.date_formats
      end
    end

    describe "DateFormats" do
      it "holds only the primary to a round-trip, so a lenient list may carry %y" do
        assert_equal ["%d/%m/%Y", "%d/%m/%y"], Locale::DateFormats.validate(["%d/%m/%Y", "%d/%m/%y"])
        assert_raises(ArgumentError) { Locale::DateFormats.validate(["%d/%m/%y", "%d/%m/%Y"]) }
      end

      it "rejects a pattern strptime cannot use, wherever it sits" do
        assert_raises(ArgumentError) { Locale::DateFormats.validate(["%Y-%m-%d", "%-d.%-m.%Y"]) }
        assert_raises(ArgumentError) { Locale::DateFormats.validate(["%Y-%m-%d", "%x"]) }
      end

      it "widens %y to %Y and leaves a literal percent alone" do
        assert_equal "%d/%m/%Y", Locale::DateFormats.widen("%d/%m/%y")
        assert_equal "%Y-%m-%d", Locale::DateFormats.widen("%Y-%m-%d")
        assert_equal "100%%y", Locale::DateFormats.widen("100%%y") # %% is a literal %, then a y
      end
    end

    describe ".system" do
      it "detects nothing when the environment says nothing" do
        assert_same Locale::ISO, Locale.system(env: {})
        assert_same Locale::ISO, Locale.system(env: { "LANG" => "C.UTF-8" })
        assert_same Locale::ISO, Locale.system(env: { "LC_ALL" => "POSIX" })
      end

      it "never raises, whatever the machine turns out to be" do
        assert_kind_of Locale, Locale.system
      end
    end

    describe ".from_keywords" do
      it "widens the detected primary and keeps the raw one behind it" do
        locale = Locale.from_keywords(keywords(d_fmt: "%d/%m/%y"), env: spoken)
        assert_equal ["%d/%m/%Y", "%d/%m/%y", "%Y-%m-%d"], locale.date_formats
      end

      it "converts glibc's Sunday-first 1-based first_weekday into Date#wday numbering" do
        assert_equal 1, Locale.from_keywords(keywords(first_weekday: "2"), env: spoken).first_weekday
        assert_equal 0, Locale.from_keywords(keywords(first_weekday: "1"), env: spoken).first_weekday
      end

      it "takes the names as given" do
        locale = Locale.from_keywords(keywords, env: spoken)
        assert_equal "M9", locale.month_names[9]
        assert_equal "m9", locale.abbr_month_names[9]
        assert_equal "So", locale.day_names[0]
        assert_equal ",", locale.decimal_separator
      end

      it "keeps each half only if its own POSIX chain speaks" do
        time_only = Locale.from_keywords(keywords, env: { "LC_TIME" => "de_DE.UTF-8" })
        assert_equal "M9", time_only.month_names[9]
        assert_equal ".", time_only.decimal_separator # LC_NUMERIC said nothing

        numeric_only = Locale.from_keywords(keywords, env: { "LC_NUMERIC" => "de_DE.UTF-8" })
        assert_equal ",", numeric_only.decimal_separator
        assert_equal Locale::ISO.date_formats, numeric_only.date_formats # …and neither did LC_TIME
      end

      it "falls back per member, not all-or-nothing" do
        locale = Locale.from_keywords(
          keywords(d_fmt: "%q", first_weekday: "9", mon: "only;two", decimal_point: "xx"), env: spoken
        )
        assert_equal Locale::ISO.date_formats, locale.date_formats
        assert_equal Locale::ISO.first_weekday, locale.first_weekday
        assert_equal Locale::ISO.month_names, locale.month_names
        assert_equal Locale::ISO.decimal_separator, locale.decimal_separator
        assert_equal "m9", locale.abbr_month_names[9] # the keys that did hold up still land
      end

      it "survives an answer with nothing in it" do
        assert_equal Locale::ISO, Locale.from_keywords({}, env: spoken)
      end
    end

    describe "Screen#locale" do
      before { Screen.fake }
      after { Screen.close }

      it "is pinned to ISO by the fake, so no example probes the machine" do
        assert_same Locale::ISO, Screen.instance.locale
      end

      it "fires on_locale_changed across the tree and invalidates it" do
        label = Component::Label.new
        Screen.instance.content = label
        seen = 0
        label.on_locale_changed = -> { seen += 1 }
        Screen.instance.invalidated_clear

        Screen.instance.locale = Locale::ISO.with(decimal_separator: ",")
        assert_equal 1, seen
        assert Screen.instance.invalidated?(label)
      end

      it "is a no-op when the locale is unchanged" do
        label = Component::Label.new
        Screen.instance.content = label
        seen = 0
        label.on_locale_changed = -> { seen += 1 }
        Screen.instance.locale = Locale::ISO
        assert_equal 0, seen
      end

      it "refuses anything that is not a Locale" do
        assert_raises(TypeError) { Screen.instance.locale = "en_GB" }
      end
    end

    describe "Screen.instance?" do
      it "answers rather than raising when there is no screen" do
        refute Screen.instance?
        assert_raises(Tuile::Error) { Screen.instance }
        Screen.fake
        assert Screen.instance?
      ensure
        Screen.close
      end
    end
  end
end
