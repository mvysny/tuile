# `Locale`: one home for the formatting conventions

**Status:** filed 2026-09-04, out of the `ideas/date-field.md` brainstorm.
Nothing here is built. `DateField` v1 ships a deliberate **stopgap** —
`DateField.default_format`, one ISO String, marked "may change" in its rdoc —
and this note is the plan that deletes it. Graduates into a `D_locale`, a
`Locale` rdoc, a book section and a CHANGELOG line.

The question is *not* "should Tuile do i18n" (it should not, see the boundary
below). It is: three components now need locale-shaped *data*, Ruby supplies
none of it, and they are about to grow three separate class-globals for it.

## Why a seam at all — three consumers, two of them already filed

- **`FloatField`'s decimal comma.** `D_float_field` rejected it verbatim:
  *"no locale seam exists in Tuile, and inventing one for a single field would
  put i18n in the wrong layer."* That is a decision explicitly deferred to this
  note.
- **The phase-2 calendar grid** (`ideas/date-field.md`, Tier 2 of
  `ideas/new-components.md`) needs month names, weekday abbreviations and
  first-day-of-week. Ruby has `Date::MONTHNAMES` / `DAYNAMES` and they are
  **frozen English**, so that grid *cannot* be built without this seam. Not
  speculative growth.
- **`DateField#formats`** — the third, and the one forcing the timing.

**And one consumer that must stay out, or this becomes an i18n subsystem.**
`D_bad_input` already ruled that wording arrives as *the wording fork* — a
settable message or a catalogue lookup inside `bad_input_message` — never as a
redesign of the channel. A message catalogue (per-string lookup, interpolation,
pluralization) is a different beast from a bag of formatting conventions. So the
boundary rule, written on day one and worth more than anything else in this
note:

> **`Locale` holds formatting conventions — how a value is rendered and parsed.
> It never holds prose.**

That sentence is what keeps this ~15 lines instead of a subsystem.

## What Ruby offers: nothing usable

Verified on Ruby 3.3.8 / glibc, not remembered:

- **No stdlib API exposes the locale's date pattern at all.** No `nl_langinfo`
  binding, no `D_FMT`, nothing on `Date`, nothing in `Etc`.
  `Encoding.locale_charmap` is the only locale-derived value in stdlib and it is
  a charset. `RbConfig` carries a `localedir` path and no data. (Version
  managers — rbenv, rvm — carry nothing; they manage Ruby, not locales.)
- **The name tables are fixed English.** `Date::MONTHNAMES[9] == "September"`
  under any `LC_ALL`, and the constant is frozen.
- **`%x` is a fixed pattern, not a lookup — and it is a trap.** Ruby's
  `strftime("%x")` returned `"09/04/26"` under every locale tried, *and*
  `Date.strptime("09/04/26", "%x")` parses, meaning `%x` in a format list is a
  silently American `%m/%d/%y` that would pass a round-trip validator. Reject
  `%x` / `%X` / `%c` explicitly wherever formats are validated, with a message
  saying Ruby's `%x` is not locale-aware — that misconception is the whole
  reason this note exists.
- **The ecosystem has the data and we will not take it.** The `i18n` gem
  (rails-i18n ships `date.formats.*` per locale) and the CLDR gems
  (`ruby-cldr`, `twitter_cldr`) are real and correct; both are dependencies, and
  Tuile's *one* optional dependency has a whole `D_` entry justifying it
  (`D_bigdecimal_field`, which explicitly says a second one needs its own
  argument, not that precedent).

## The detection path: ask `locale(1)`

Ruby cannot read the locale, but `locale(1)` can — and it hands back **strftime
patterns, Tuile's exact vocabulary**, so there is no second grammar to translate
or keep correct. One call seeds the whole object:

```console
$ locale d_fmt abmon first_weekday
%Y-%m-%d
Jan;Feb;Mar;Apr;May;Jun;Jul;Aug;Sep;Oct;Nov;Dec
2                     # 1-based index into `day`, so Monday
```

That is `DateField`'s primary format *and* the calendar grid's month names and
first-day-of-week, from one ~1.4 ms subprocess. It also keeps the
**no-catalogue** rule better than shipping locale constants would: Tuile ships
*zero* locale data and asks the system.

**The worked example that settles it** — the author's own machine, deliberately
configured:

```
LANG=en_US.UTF-8        # I want an English UI
LC_TIME=en_DK.UTF-8     # I do not want American dates
$ locale d_fmt
%Y-%m-%d
```

POSIX precedence is `LC_ALL` > `LC_TIME` > `LANG`, libc applies it, and the
answer is the one the user arranged. Read two env vars and "disagree" and you
have invented an ambiguity the standard already resolved.

**So do not write the cheap version.** `ENV["LC_ALL"] || ENV["LC_TIME"] ||
ENV["LANG"]` plus a locale-name → format table is the catalogue *plus* a
reimplementation of libc's chain, and it gets `en_DK` wrong unless the table
happens to carry it. The subprocess's value is not that it reads env vars — it
is that it reads the **compiled locale data**.

This also reverses the tentative ruling `ideas/date-field.md` carried
("detect the parsing leniency if anything; keep what the field writes back
fixed"): a user sets `LC_TIME` precisely because they want to *see* dates
differently, so detection that does not move the display format gives them
nothing.

## Four gotchas, all found by probing, all cheap

1. **The exit code is useless.** A bad locale prints to stderr, **exits 0**, and
   silently returns the C locale (`LC_ALL=xx_YY.UTF-8 locale d_fmt` →
   `%m/%d/%y`, status 0). Suppress stderr and validate the *shape* of what came
   back — a pattern carrying year/month/day directives — never the status.
2. **No preference at all also yields `%m/%d/%y`.** The C/POSIX default is
   American, so "the user said nothing" and "the user wants American" are
   indistinguishable, and a container with no `LANG` would silently show
   American dates to everyone. Hence the rule, which is also the honest
   statement of intent: **detect only when the user actually said something** —
   if none of `LC_ALL` / `LC_TIME` / `LANG` is set (or they are `C` / `POSIX`),
   skip the probe and use ISO. *This is the one judgement call the whole design
   rests on; everything else falls out of it.*
3. **`en_GB`'s `d_fmt` is `%d/%m/%y`, and that is a data bug rather than a
   matter of taste.** It is the case that survives doing detection *correctly*,
   and it has a principled fix instead of a fudge: a two-digit year cannot
   round-trip. `Date.new(1962, 9, 4).strftime("%d/%m/%y")` → `"04/09/62"` →
   reparses as **2062**, because Ruby's `%y` uses the fixed POSIX window
   (`69`→1969, `26`→2026). So the rule is not "Tuile second-guesses the locale",
   it is the round-trip validator run with a reference date outside that window:
   **the primary format must round-trip every `Date`, and `%y` fails.** The
   detected primary is therefore widened `%y`→`%Y`, while the raw `d_fmt` stays
   in the *parse* list so a Brit typing `04/09/26` is still understood — lenient
   in, strict out, the field's own design doing real work. Detected list:
   `[widened, raw, "%Y-%m-%d"].uniq`.
4. **Portability, and the precedent this sets.** `locale` is POSIX and present
   on macOS (**unverified** — check before building); busybox / musl containers
   may lack it or stub it out. Fallback to ISO covers all of that. But name the
   real cost honestly in the `D_`: **a subprocess at `Screen` construction is a
   first for Tuile.** `ColorDepth.detect` is env-only, `TerminalBackground`
   is an OSC query on a stream Tuile already owns. That, not correctness, is the
   thing the decision has to argue.

## Shape: copy `ThemeDef`, line for line

Tuile has already solved this problem once, and the parallel is exact:

| Theme | Locale |
|---|---|
| `Theme` — frozen value type of tokens | `Locale` — frozen value type of conventions |
| `ThemeDef.default` seeds new screens | `Locale.default` seeds new screens |
| `Screen#theme` / `#theme_def=` | `Screen#locale` / `#locale=` |
| read at *paint* time, never cached in an ivar | read at *use* time, never cached |
| `bg_color=` overrides per component | `formats=` overrides per field |
| detected once in `Screen#initialize` | same |
| `FakeScreen` pins it for determinism | same |

```ruby
Locale = Data.define(:date_formats)   # …month_names, first_weekday, decimal_separator later
Locale::ISO = Locale.new(date_formats: ["%Y-%m-%d"].freeze)
```

Two consequences worth stating rather than re-deriving:

- **Hanging the live value off `Screen` is what kills the spec-leak hazard.**
  AGENTS.md warns that a spec reassigning `ThemeDef.default` or
  `VerticalScrollBar.handle_char` must restore it or every later example reads
  the leaked value. Here a spec sets `screen.locale` and the next `Screen.fake`
  resets it; only `Locale.default` leaks, and it is a *seed* rather than the
  value anything reads. That is exactly why `ThemeDef.default` seeds rather than
  being read directly.
- **Ship exactly one constant, `Locale::ISO`.** No `EN_US`, no `DE`. Two presets
  is a catalogue, a catalogue implies completeness, and `en_GB`'s `%d/%m/%y`
  shows how opinionated even a "correct" entry is. Apps build their own with
  `ISO.with(date_formats: [...])`. Tuile hands over the gun and ships no
  ammunition presets.

Plus the `ColorDepth` escape hatch for symmetry: an env override
(`TUILE_DATE_FORMATS`, or a broader `TUILE_LOCALE`) that wins over the probe —
which is also how a PTY spec would pin it, per AGENTS.md's colour-depth note.

## Still open

- **Whether the subprocess is acceptable at all**, which is gotcha 4 and the
  real content of the future `D_`. The fallback if it is not: no detection, ISO
  default, apps configure `Locale.default` themselves. That is strictly the
  status quo plus a home, and it is still an improvement on three class-globals.
- **macOS / BSD `locale` keyword support** — believed fine, not verified.
- **Non-ASCII month names walk straight into the ambiguous-width bet.** `locale
  abmon` in a CJK locale returns glyphs a calendar grid has to *measure*
  (`D_ambiguous_width`, `D_cluster_width`). The grid's column arithmetic must go
  through `columns_of` / `display_width` like everything else — worth knowing
  before the grid is designed, since a month-name header is the first place
  Tuile would paint text it did not choose.
- **The decimal separator is not a free ride.** `FloatField`'s `TYPEABLE` is an
  `insert_text` filter, and admitting `,` changes what AGENTS.md's own worked
  example says (`"1,5"` pasted currently lands *nothing*, deliberately, rather
  than sieving to `"15"`). A comma grammar is still prefix-closed so
  `D_input_filters` holds, but the field would then need to know which separator
  is live *at parse time* as well as at filter time — and `value=` writes with
  `to_s`, which is always a dot. Decide with the field, not here.
- **Does a locale belong on `Screen` at all?** It is a property of the human,
  not of the terminal, and `Screen` is "the service". It fits the
  machinery-on-`Screen` rule (`D_tree_first`) and there is nowhere else, but the
  objection is real and should be answered in the `D_` rather than ignored.
- **What a mid-run `locale=` does.** `theme=` invalidates the whole tree; the
  same is presumably right here, but a `DateField` holding a half-typed buffer
  under the old primary format is a case `theme=` does not have.

## Related

`ideas/date-field.md` (the note this came out of; the v1 stopgap
`DateField.default_format` that this deletes, and the format-list / placeholder
rulings that stand either way), `D_float_field` (the decimal comma deferred to
this seam, verbatim), `D_bad_input` (the wording fork that must **not** come
here), `D_bigdecimal_field` (why a gem dependency needs its own argument),
`D_color_depth` and `ColorDepth.detect` (detect once, env overrides, pin in the
fake — the pattern being copied), `D_background_rgb` (the other probe, and why
its timing is load-bearing), `D_theme_ref` and AGENTS.md "Theme" (the
`ThemeDef.default`-seeds-new-screens shape, and the spec-restore warning),
`D_ambiguous_width` / `D_cluster_width` (measuring month names Tuile did not
choose), `D_input_filters` (the decimal-separator interaction),
`D_tree_first` (machinery on `Screen`),
`ideas/new-components.md` (Tier 2 calendar grid).
