# `TimeField`: the time of day, with no date and no zone

**Status:** filed 2026-09-04. Nothing built. Read `D_date_field` first — this
note is deliberately its twin and only writes down where the twin *diverges*;
every ruling not questioned below is inherited verbatim. Findings marked
**verified** were run in this repo's Ruby (`ruby -rdate`), not predicted.

The component: a one-row field whose value is a **local time of day** — a wall
clock reading, no date attached and no zone attached. `09:30` means half past
nine wherever you are.

## The value type — the one question to settle before building

Ruby has no civil-time class. That is the whole difficulty, and it is why this
cannot just copy `D_date_field`'s answer: that entry could say "Ruby's `Date`
*is* the civil date" and stop. Four candidates, and the naming rule
(`D_float_field`: a typed field is named after the Ruby class of its value)
prices each one.

| Value | Component name | Cost |
|---|---|---|
| `Time` on a fixed epoch date, in UTC | `TimeField` | the value is a real *instant*, so it can be passed where an instant is wanted |
| `Tuile::LocalTime` (`Data.define`) | `LocalTimeField` | Tuile ships a domain value type; every app converts at its own boundary |
| `Integer` seconds since midnight | — (`IntegerField` by the rule) | indistinguishable from a duration; the name is not derivable |
| `String` | — | that is a `TextField`; no typed field at all |

**Decided 2026-09-04: `Time`, pinned to a fixed epoch date in UTC — so the
component is `TimeField`** — on the grounds that it is what an app is most
likely to be holding already, with a `LocalTimeField` over a Tuile-owned value
type left open as a *supplement* rather than a replacement (see the end of this
section). The argument that decides it is a sharpening of
`D_date_field`'s "Tuile's job is to edit the app's values, not to introduce its
own", which needs sharpening precisely because there is no stdlib type to defer
to here:

> Tuile owns **UI** value types — `Point`, `Size`, `Rect`, `Fraction`, `Color`,
> `StyledString`, `Theme`, `Locale`. It owns no **domain** value types, and a
> time of day is domain data: it lands in a model, a column, a serializer.

That is a rule with a stated edge rather than a preference, and it survives the
observation that the ecosystem has no consensus type either — because the
ecosystem's *near*-consensus is exactly this shape: a `Time` on a dummy date is
what Rails' `time` column and Sequel's `SQLTime` both hand you.

**Unverified, and worth ten minutes before building:** that Rails' dummy date is
`2000-01-01` (recollection, gem not installed here — `gem install activerecord`
then `ActiveRecord::Type::Time.new.cast("13:45")`) and what `Sequel::SQLTime`
uses. If Rails' is 2000-01-01, picking the same epoch makes an
ActiveRecord-backed round-trip exact and turns this choice into *alignment with
an existing convention* rather than a Tuile invention — which is the strongest
version of the argument. If it turns out to be something else, the epoch is a
one-constant change, and matching Rails still wins.

**UTC, not local, and that is not a detail.** A local epoch would put every
value on a date whose offset the zone can change — a zone with a transition on
the epoch date makes some wall times unrepresentable or silently shifted, which
is the whole DST class. UTC removes it. The cells still read correctly, because
`hour` / `min` / `sec` / `strftime` on a UTC `Time` report UTC (**verified**:
`Time.utc(2000,1,1,13,45,0).strftime("%H:%M") # => "13:45"`).

**The accepted cost, stated once and loudly in rdoc.** The value is an instant,
so it can be *wrong* somewhere else while being a perfectly good `Time`:

```ruby
field.value = Time.now             # takes the wall clock it reads on its own clock
field.value                        # => 2000-01-01 13:45:00 UTC
field.value == Time.now            # => false — verified; different date, different zone
```

An app that forgets to combine it with a date gets the year 2000 in its output —
*visible*, which by this project's standard beats silently wrong. `value=` stays
thin and lenient the way `DateField#value=` is: take the receiver's own `hour` /
`min` / `sec` and rebuild on the epoch, so `Time`, `DateTime` and
`Sequel::SQLTime` all just work and the truncation is one documented sentence.

Two ergonomics that follow, both cheap:

- `TimeField.at(hour, minute, second = 0)` — the canonical constructor an app
  and a spec compare against, so nobody hand-writes the epoch date.
- The epoch as a public frozen constant (`MIDNIGHT`, a `Time`), because rdoc has
  to name it anyway.

**Why not `LocalTime`, given it makes the wrong state unrepresentable.** It
does, and that is a real argument — a `NoMethodError` beats the year 2000. It
loses on the rule above plus a cost the table understates: owning a value type
means owning `Comparable`, arithmetic, `to_s`, `inspect`, RBS signatures and a
spec file, in a toolkit whose job is editing. And it buys nothing for the
composite: `DateTimeField` combining a `Date` with either representation is one
line. **Re-argue it if** an app is observed passing a `TimeField#value`
somewhere it means an instant — that is the failure this trades away.

**As a later *supplement*, though, it stays open and stays cheap**, because the
naming rule makes the two coexist without a mode flag: `TimeField#value` is a
`Time`, `LocalTimeField#value` is a `Tuile::LocalTime`, and an app picks by
which type its model speaks. Two notes for whoever adds it. It would be the
**third** copy of this shell (`DateField`, `TimeField`, then it), which is the
count `D_float_field` names as the moment to re-argue duplication — and the
honest answer will probably still be "duplicate", since what differs is the
parse and the value and what is shared is ~15 lines. And it must **not** arrive
as a `value_type:` knob on `TimeField`: that is the injected-converter strategy
`D_integer_field` refused, and it would make `value`'s class un-derivable from
the component's name.

## What it copies from `DateField`, unchanged

This is a **deliberate near-copy**, the second of the date-field shell exactly
as `FloatField` is the second of the numeric one (`D_float_field`), and the same
rule applies: duplicate rather than DRY, re-argue at the fourth copy. Copied
without re-deciding:

- `AbstractWrappingField` + a `TextField` editor, `include HasBadInput`,
  `empty_value = nil`, no `extent` and no paint code of its own.
- **The format list**: parse in order, first whole match wins, `formats.first`
  is written by `value=` and rewritten into on commit. Lenient in, strict out.
- **No input filter, at all.** The grammar is not prefix-closed (`"1"` is a
  prefix of `"13:45"` and is not a time), so every character is admitted and the
  residue is reported through `bad_input?` — including the tempting middle
  `D_input_filters` refuses, since a partial filter reads as a guarantee.
- **The red well latched to the commit gestures** (`bad_input_settled?`), for
  the identical reason: every prefix of a time is bad input.
- `formats` / (any other locale-derived knob) are **nil-means-inherit** readers
  over `Screen#locale`, with `on_locale_changed` re-deriving the placeholder and
  rewriting a buffer that still parses.
- The placeholder derived from the primary format, **exactly or not at all**.
- Up/Down claim the editor's arrow slots; an empty field steps to *now*.
- `MAX_TEXT_LENGTH = 64` — a pasted-novel guard, not a grammar.
- `bad_input_message` a frozen constant: `"not a valid time"`.

`calendar_start` has no analogue and is not carried over.

## Where it must diverge — the parse needs a third gate

`DateField`'s parse is two gates: a non-empty `:leftover` is no match, and
constructing the `Date` catches February 30th. **The second gate does not
transfer, because `Time` normalizes where `Date` raised** (all **verified**):

```
Date._strptime("24:00", "%H:%M")        # => {hour: 24, min: 0}
Time.utc(2000,1,1,24,0,0)               # => 2000-01-02 00:00:00 UTC   ← next day, silently
Date._strptime("13:45:60", "%H:%M:%S")  # => {hour: 13, min: 45, sec: 60}
Time.utc(2000,1,1,13,45,60)             # => 2000-01-01 13:46:00 UTC   ← rolls over, silently
```

Both are wrong-values-that-save-cleanly, and the second one is worse than it
looks: a rollover past midnight lands the value on a *different date* than every
other value the field produces, so comparison and sorting quietly break. So
`TimeField` range-checks `hour` 0..23, `min` 0..59, `sec` 0..59 itself, and
`Time.utc` becomes construction rather than validation.

Two things that need no gate of their own (**verified**): `Date._strptime`
already range-checks the *field width* — `"25:00"` and `"13:99"` both yield
`nil` — and it gives free padding leniency, `"1:45"` parsing under `%H:%M`
exactly as `"2026-9-4"` parses under `%Y-%m-%d`. Which is the same argument for
canonicalizing on commit.

`24:00` being rejected costs one documented sentence: it is a legal ISO 8601
end-of-day and `Time` cannot hold it.

**No new `require`.** The parse is `Date._strptime` (and `date` is already
hoisted into `lib/tuile.rb` per `D_date_field`); `Time` is core, and
`Time.strptime` — the one thing that would need `require "time"` — is not used.

### Stepping wraps, because a time of day is cyclic

Up/Down step **one minute** and wrap modulo 24 h: `23:59` + 1 → `00:00`. A date
never posed this question; a clock has no day to carry into, so wrapping is not
a policy choice but the arithmetic. An empty or unparseable field steps to
**now** (the local wall clock, truncated to the primary's precision), which is
the `Date.today` analogue and lands *on* now rather than now ± 1.

Deferred, recorded so it is a decision: PageUp/PageDown stepping an hour, for
symmetry with `D_date_field` deferring the month step. A `step=` knob (Vaadin's
`TimePicker` has one) is deferred with it — it is additive, and it is really a
question about the picker of phase 2.

## Formats: the locale owns the spelling, the app owns the precision

**The default is one format, `%H:%M`.** `D_date_field`'s
ambiguity argument does not bite here — no string matches both `%H:%M` and
`%H:%M:%S`, so a lenient default would be *safe* — but a different argument
lands in the same place, and it is the one new ruling this field makes:

> **Precision is not a spelling.** A format list is ordered leniency, and for
> time the order also decides *how much of the value survives a commit*. Only
> the widening direction is lossless: with `%H:%M:%S` primary, typing `13:45`
> canonicalizes to `13:45:00` and adds nothing false. With `%H:%M` primary,
> typing `13:45:30` canonicalizes to `13:45` and **loses the seconds** — the
> buffer is the single source of truth, so truncating the buffer truncates the
> value.
>
> So the shipped default accepts *only* `%H:%M`, and `13:45:30` is bad input:
> visible, reportable, fixable. An app that wants seconds writes
> `field.formats = "%H:%M:%S"` and gets the lossless direction for free; an app
> that deliberately wants lossy leniency writes `["%H:%M", "%H:%M:%S"]`, which
> is its call in exactly the way the date order is its call.

The same rule decides what **detection** does with `t_fmt`, and it is the
non-obvious half: glibc's `t_fmt` is a *clock display* format, so it carries
seconds nearly everywhere. Honoring it would put `:00` in every form field in
the world. So detection **keeps the locale's spelling and drops its precision** —
the separator, the digit order and the 12/24-hour choice are conventions, the
seconds are not.

Detected list = `[t_fmt expanded and stripped of seconds, ISO]`, uniq — the same
shape as `date_formats_from`'s `[widened, raw, ISO]`, with the *raw* entry
dropped for the reason above. **Verified** against the locales actually
generated on this box (only `%H:%M` and `%H.%M.%S` and `%r` and `%T` occur, and
the C row is moot since `C` counts as silence):

| locale | `t_fmt` | primary | writes | list |
|---|---|---|---|---|
| en_US | `%r` | `%I:%M %p` | `01:45 PM` | `["%I:%M %p", "%H:%M"]` |
| en_GB | `%T` | `%H:%M` | `13:45` | `["%H:%M"]` |
| fi_FI | `%H.%M.%S` | `%H.%M` | `13.45` | `["%H.%M", "%H:%M"]` |
| C | `%H:%M:%S` | `%H:%M` | `13:45` | `["%H:%M"]` |

So the expansion table is needed at the boundary anyway (`%T` → `%H:%M:%S`,
`%R` → `%H:%M`, `%r` → `%I:%M:%S %p`) — **verified** as the honest reason to
have one: it is not just tidiness, it is what lets the placeholder derive. Note
`t_fmt_ampm` is **not** read: en_GB's is `%l:%M:%S %P %Z`, which carries a zone
name and a blank-padded 12-hour hour, i.e. two directives this field rejects.

### The round-trip reference is a `Time`, and every property is load-bearing

`REF = Time.utc(2000, 1, 1, 13, 45, 0)` — the epoch date plus a canary time:

- **hour ≥ 13**, so a 12-hour directive with no `%p` fails. This is the exact
  analogue of `%y` not carrying a century, and it is free: **verified**,
  `%I:%M` writes `"01:45"` and reads back 1 o'clock, so the round-trip catches
  it, while `%I:%M %p`, `%I.%M %p` and `%I:%M%P` all pass.
- **minute ≠ hour**, so an `%H`/`%M` swap is not masked.
- **second = 0**, so a minute-precision primary is legal — which the shipped
  default is.

And what it deliberately does **not** catch, stated the way `D_date_field`
states the order ambiguity: a **precision truncation**. `%H:%M` round-trips
itself perfectly, and how precise the field is, is the app's call.

**Verified** to pass: `%H:%M`, `%H:%M:%S`, `%T`, `%R`, `%r`, `%H.%M`, `%Hh%M`,
`%H%M`, `%k:%M`, `%I:%M %p`. **Verified** to be rejected: `%I:%M`, `%I:%M:%S`,
`%l:%M`, `%p`, `%H`, `%M:%S`, `%s`, and any `%-H` (strptime takes no `-` flag).

### Two new rejected-by-name lists, both for silent loss

`%x` / `%X` / `%c` are already rejected by name as locale lookalikes and stay
rejected. Two more classes need it, because they **round-trip cleanly and lose
information anyway** (all **verified**):

- **Zone directives** — `%z`, `%Z`, `%:z`, `%::z`, `%s`. `"%H:%M:%S%z"`
  round-trips (it writes `+0000` and reads it back), and
  `Date._strptime("13:45:00+0200", "%H:%M:%S%z")` hands back `zone: "+0200",
  offset: 7200` — which this field *drops on the floor*. A user typing an offset
  would see it silently reinterpreted as a local wall time. The field has no
  zone by decision, so a format claiming one is refused, with a message that
  says so.
- **Sub-second directives** — `%L`, `%N`. `"%H:%M:%S.%L"` round-trips (the
  reference's fraction is 0) and `Date._strptime("13:45:00.500", …)` yields
  `sec_fraction: (1/2)`, dropped. A time of day holds whole seconds; say it at
  assignment.

One known limitation to write down rather than fix: **Ruby's `%p` is fixed
English.** Under a 12-hour locale whose `am_pm` is not `AM;PM`, the field writes
English. Implementing `%p` from `Locale#am_pm` would mean owning a second
formatting grammar, which `D_date_field`'s "strftime, not Java patterns" ruling
already refuses. Most 12-hour locales are English; the cost is real and small.

## `Locale` grows its ninth member

`locale.rb`'s rdoc says *"That is the rule a ninth member has to pass"*, and
`time_formats` passes it cleanly: it is how a value is rendered and parsed, and
it is no part of prose. Concretely:

- `Locale#time_formats`, validated like `date_formats`; `Locale::ISO` gets
  `["%H:%M"]` (ISO 8601 permits reduced accuracy `hh:mm`, and the UI default
  argument above picks it).
- `KEYWORDS` gains `t_fmt`. **Not** `t_fmt_ampm` and **not** `am_pm`, per above.
- `Locale.system`'s existing `LC_TIME` gate covers it — no new category.
- Detection normalizes at the boundary (expand, strip seconds), never at the
  consumer, exactly as `first_weekday` and `widen` already do.
- Specs drive it through `Locale.from_keywords` with canned answers, and
  `FakeScreen` keeps pinning `Locale::ISO`, so no example shells out.

### The one refactor this forces: hoist the format lexer

`Locale::DateFormats` holds two kinds of thing: a **lexer** over strftime
patterns (`DIRECTIVE`, `each_directive`, `LOCALE_LOOKALIKES`) and a
**validator** for dates (`REF`, `HINTS`, `widen`, `round_trips?`). A
`TimeFormats` sibling needs its own validator — a `Time` reference, its own
`HINTS`, its own by-name rejections, no `widen` — but the same lexer, and
duplicating a regex-plus-`StringScanner` is not what "duplicate rather than DRY
a shallow shell" is about (that rule is about component shells; this is a lexer,
and two copies of `DIRECTIVE` drifting apart is a silent bug in both).

Proposal: hoist the three lexer members into `Locale::Formats` and leave two
validator modules over it — `DateFormats` and `TimeFormats`, each keeping its
own public name and API. Moving three constants is a **Breaking** CHANGELOG line
in a pre-1.0 gem; taking it now is cheaper than a third format kind later.

Keeping the two `HINTS` tables separate falls out of that split, which is good:
`%m` → `mm` (month) and `%M` → `mm` (minute) are both correct in their own
table, and a combined table is a question only a `DateTimeField` has to ask.
`TimeFormats::HINTS` = `%H`/`%I` → `hh`, `%M` → `mm`, `%S` → `ss`,
`%p` → `AM`, `%P` → `am`, `%%` → `%`. `%p` is admissible where `%b` was not:
`mmm` would be an invented token, while `AM` is literally what the field prints,
and a placeholder is a typing *sample*. So en_US's derived hint is `hh:mm AM`
and fi_FI's is `hh.mm`.

## Phase 2, and the composite

A **picker dropdown is cheap here**, unlike `DateField`'s calendar grid: a list
of times at a step interval is a `ListDropdown` of strings driven the way
`Select` drives one, with no new machinery and no Popover extraction. Still not
v1 — v1 is manual entry, as `DateField`'s was — but it is a much shorter
follow-up, and it is where a `step=` knob would earn its place.

Building this also gives `ideas/composite-field.md` its real consumer:
`DateTimeField` over a `DateField` plus a `TimeField` is the shape that note was
filed for, and it is still blocked on the question that note leaves open (which
component wears a *combination* error), not on this one.

## What shipping owes, beyond the code

The four registrations `AGENTS.md` names — rdoc, the CHANGELOG, the layout list,
the README row — plus this field's own extras: rdoc on
the class; a `D_time_field` entry in `DECISIONS.md` (with the value-type
argument above as its spine, and a pointer from `D_date_field`); a CHANGELOG
`Add` line (plus the `Breaking:` line for the lexer hoist, and an `Add` for
`Locale#time_formats`); a `README.md` Components row; the `AGENTS.md` layout
list; book ch7 beside `DateField` and a ch10 mention for `time_formats`; a
`spec/tuile/component/time_field_spec.rb` mirror; a sampler pane under
Input → Typed; and a regenerated `sig/tuile.rbs`.

## Related

`D_date_field` (the twin, and every ruling not questioned here),
`D_locale` (the conventions seam and its nil-means-inherit knobs),
`D_bad_input` (accept-and-report, and the settling rule this is the second
consumer of), `D_input_filters` (why a prefix-closed grammar is the condition,
and why a partial filter is refused), `D_wrapping_field` (the base and its
commit seam), `D_float_field` (the naming rule, and duplicate-rather-than-DRY),
`ideas/composite-field.md` (`DateTimeField`, the consumer this unblocks),
`ideas/new-components.md` (the Tier 2 row naming the Time / DateTime twins,
which this note retires from that table when it graduates).
