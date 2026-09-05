# `TimeField`: the time of day, with no date and no zone

**Status:** filed 2026-09-04; precedent survey added and the precision knob
settled as `step` (superseding a same-day two-knob ruling, kept under *Re-grow*)
2026-09-05. Nothing built.
Read `D_date_field` first — this
note is deliberately its twin and only writes down where the twin *diverges*;
every ruling not questioned below is inherited verbatim. Findings marked
**verified** were run in this repo's Ruby (`ruby -rdate`), not predicted;
findings marked **surveyed** were read off another toolkit's own documentation
or source, which is a weaker claim and is kept a separate word for that reason.

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

**Ruled `MIDNIGHT = Time.utc(2000, 1, 1)`, pending one verification** (worth ten
minutes before building; gem not installed here — `gem install activerecord` then
`ActiveModel::Type::Time.new.cast("13:45")`). The recollection is that Rails
builds on `2000-01-01`, and that `Sequel::SQLTime` defaults to *today* with a
class-configurable date — which means Sequel cannot be matched by *any* fixed
epoch, so Rails is the one convention there is to align with. If Rails' date
holds, an ActiveRecord-backed round-trip is exact and this choice is *alignment
with an existing convention* rather than a Tuile invention, which is the
strongest version of the argument. If it turns out to be something else, the
epoch is a one-constant change, and matching Rails still wins.

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

**What `value=` accepts, ruled:** anything responding to `hour` / `min` / `sec`
is taken by those three readers; `nil` clears; a `Date` raises `TypeError` (it
has no hour to take — accepting it would mean inventing midnight), and so does a
`String` (that is what the *buffer* is for, and a `value=` that parsed would be a
second parse path with its own leniency). Sub-seconds are truncated silently, per
the `%L` ruling below — a time of day holds whole seconds.

Two ergonomics that follow, both cheap:

- `TimeField.at(hour, minute, second = 0)` — the canonical constructor an app
  and a spec compare against, so nobody hand-writes the epoch date. **It shares
  the parse's range gate** (next section): `Time.utc(2000, 1, 1, 24, 0, 0)`
  normalizes to the next day just as silently from a constructor as from a parse,
  so `at(24, 0)` raises `ArgumentError` — otherwise a spec comparing against it
  passes against a value on the wrong date.
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
  (*Where the list comes from* diverges — it is derived, with no per-field
  writer; see Formats. How it is *consumed* is copied verbatim.)
- **No input filter, at all.** The grammar is not prefix-closed (`"1"` is a
  prefix of `"13:45"` and is not a time), so every character is admitted and the
  residue is reported through `bad_input?` — including the tempting middle
  `D_input_filters` refuses, since a partial filter reads as a guarantee.
- **The red well latched to the commit gestures** (`bad_input_settled?`), for
  the identical reason: every prefix of a time is bad input.
- Locale-derived state is **read at use time, never snapshotted**: `formats` is
  derived from `Screen#locale` and `step` on every read, and `on_locale_changed`
  re-derives the placeholder and rewrites a buffer that still parses. The
  difference from `DateField` is that here nothing is nil-means-inherit because
  nothing is overridable per field — the stored knob is `step`, and it is not
  locale-derived. A `step=` that eagerly resolved a format list would snapshot
  the locale, which is the failure `AGENTS.md` names under Locale.
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
`Time.utc` becomes construction rather than validation. **The same gate guards
`TimeField.at`** — one private range check, two callers, so the constructor and
the parse cannot drift on what a legal time is.

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

Up/Down step by **`step`** (an Integer number of seconds, default **60**) and
wrap modulo 24 h: `23:59` + 1 → `00:00`. A date never posed this question; a
clock has no day to carry into, so wrapping is not a policy choice but the
arithmetic. An empty or unparseable field steps to **now** (the local wall
clock, truncated to the field's precision), which is the `Date.today` analogue
and lands *on* now rather than now ± 1.

**Inherited knowingly: Up on a half-typed `13:4` steps to now, clobbering the
typing.** That is `DateField`'s ruling and the twin keeps it — a user pressing an
arrow mid-typo is asking for help, and a no-op is a dead key. But `D_time_field`
records it as a *shared* ruling: if it is ever changed to "step only from empty,
no-op on unparseable", both fields change in one commit, because a divergence
here reads as a bug in whichever field a user meets second.

**Stepping adds; it never snaps.** `step = 900` from `13:07` goes to `13:22`, not
to the `13:15` grid line. Snapping silently moves a value the user did not ask to
change; Vaadin adds too (*"accepts values that don't align with the specified
step"*), and HTML's snap is to a `min` base this field does not have.

**`step=` takes a positive `Integer` in `1...86400` and raises `ArgumentError`
on anything else.** No `nil` — nil-means-inherit is for locale-derived knobs and
this is not one, so the default is set in `initialize`. No `Float` or `Rational`
— a sub-second stride implies `%L`, which the field rejects by name below.
`86400` and up would wrap onto itself. `7` is legal even though it does not
divide 60; see the divisor note next.

**`step=` at runtime with a value present is the locale-change path.** Setting
it re-derives `formats` and the placeholder and then applies exactly the rule
`on_locale_changed` already has — *re-canonicalize a buffer that still parses,
leave one that does not*. Widening `60 → 1` rewrites `13:45` to `13:45:00`
(lossless, and the lenient secondaries make it parse). Narrowing `1 → 60` with
`13:45:30` in the buffer leaves it: it becomes bad input, `value` reads `nil`,
`on_value_change` fires, and `bad_input?` says why. Nothing is silent on any
channel, and the field never truncates a value it did not type — the *app*
narrowed it, and the app hears about it through the seam it already listens on.
This is also the natural implementation: `step=` is "re-derive, then run the
locale-change path", not a second code path.

**`step=` ships in v1, and it is also the precision knob** — the Formats section
owns that ruling and its costs; this section owns the stride. Two things about
the stride that are Tuile's and not Vaadin's:

- **The default is one minute, not Vaadin's one hour.** Vaadin's `3600` is a
  *dropdown-density* choice — how many rows the overlay shows — and it leaks
  into the arrow keys, so Up from `13:45` lands on `14:45`. There is no overlay
  here in v1 and a minute is what a time-of-day field's arrow key means.
- **No divisor rule.** Vaadin requires a step to divide an hour or a day evenly.
  Tuile just adds and wraps; `step = 90` walks `13:45` → `13:46:30` → `13:48:00`
  and the wrap at midnight is the only place the arithmetic notices anything.
  A constraint that exists for a picker's row grid is the picker's to add.

Deferred, recorded so it is a decision: PageUp/PageDown stepping an hour, for
symmetry with `D_date_field` deferring the month step.

## Formats: the locale owns the spelling, `step` owns the precision

**The default is minute precision.** `D_date_field`'s
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
> So the shipped default accepts *only* the minute form, and `13:45:30` is bad
> input: visible, reportable, fixable. An app that wants seconds sets the step
> below a minute and gets the lossless direction for free.

### The knob is `step`, and `formats` is a report

**Decided 2026-09-05, superseding a same-day ruling the other way** (kept below
under *Re-grow*, since it is the answer to the day a per-field format writer
comes back). The field has **one** precision-bearing knob, and it is the stride:

- **`step < 60` shows seconds; `step >= 60` does not.** That is Vaadin's rule and
  HTML's, and it is the whole of it — no `precision:` and no `formats=`. Nor a
  read-only `precision` reader to squat the name: `formats` already squats the
  one that matters, a `precision` reader invites "where is the writer?", and the
  entire API is one rdoc sentence — *seconds are shown iff `step < 60`*.
- **The two lists are not symmetric, and the asymmetry is the opening ruling
  applied.** At `step < 60`, `formats` is the *full-precision forms, then the
  stripped forms* — so typing `13:45` parses through the lenient secondary and
  canonicalizes to `13:45:00`, the lossless direction, for free. At `step >= 60`
  it is the stripped forms *only*: admitting `%H:%M:%S` there is the lossy
  direction, so `13:45:30` stays bad input. One rule, read from the primary.
- **`formats` is a read-only reader**, derived on every read from
  `Screen#locale` and `step`. It exists so the placeholder, the rdoc, the specs
  and a curious app can name the list in force, and for the reason
  `Component#size` exists: to **squat the name**, so that a writer can only ever
  return through the re-grow rule and never as an unexamined accessor.
- **The escape hatch is `screen.locale=`**, exactly as Vaadin's is `setLocale()`.
  An app that wants a spelling the probe did not find assigns a `Locale` with the
  `time_formats` it wants, and every `TimeField` follows — which is what a
  *convention* is.

Why one knob wins over the two-knob shape this note held for a day: with no
per-field format writer, there is exactly **one** writer for the precision fact,
so the contradiction that needed a ruling — an explicit `%H:%M:%S` beside a
minute precision — is not expressible, and the *spelling gap* the two-knob shape
was designed to fix does not exist to begin with. There is no override that could
drop the detected spelling, so **the locale's spelling always survives**: fi_FI
gets `13.45` and `13.45.00` and never a colon. That is MUI's outcome (below) at
the price of one knob rather than two.

**The costs, named so this is chosen and not inherited.** Vaadin arrived at the
fusion by having no format API at all (the survey below is explicit about that);
Tuile arrives by deleting one on purpose, which is a different and stronger
position only if the price is written down:

1. **Seconds precision with a minute stride is unsayable.** A field holding
   `13:45:30` whose Up key walks to `13:46:30` cannot be built; asking for the
   third segment hands you a one-second stride. Narrow — Vaadin has lived without
   it — and **additive to fix**: a `precision:` whose nil means derived-from-step
   and whose value overrides it breaks nothing that exists today.
2. **No per-field spelling override**, which makes the twin asymmetric:
   `DateField#formats=` is a writer. Defensible on the merits, not just on
   simplicity — a date has a genuine *per-field* axis (one form mixing `dd.mm.` and
   ISO for a technical value), and a time has none; 12- versus 24-hour is a
   session convention, which is what `Locale` is for.
3. **Deliberate lossy leniency** (`["%H:%M", "%H:%M:%S"]` as an app's own list) is
   gone. It was a sanctioned edge, never a need.

The same rule decides what the **field** does with `t_fmt`, and it is the
non-obvious half: glibc's `t_fmt` is a *clock display* format, so it carries
seconds nearly everywhere. Honoring it would put `:00` in every form field in
the world. So the field **keeps the locale's spelling and drops its precision** —
the separator, the digit order and the 12/24-hour choice are conventions, the
seconds are not.

**The strip runs in `TimeField`, not at the `Locale` boundary** — see the
relocation argument under the survey below. `Locale#time_formats` carries the
locale's spelling at *full detected precision*
(`[t_fmt expanded, ISO-with-seconds]`, uniq — the same shape as
`date_formats_from`'s `[widened, raw, ISO]`), and the field strips per its
`step`. **Verified** against the locales actually generated on this box
(only `%H:%M`, `%H.%M.%S`, `%r` and `%T` occur, and the C row is moot since `C`
counts as silence):

| locale | `t_fmt` | `Locale#time_formats` | `formats` at `step >= 60` (default) | writes | `formats` at `step < 60` | writes |
|---|---|---|---|---|---|---|
| en_US | `%r` | `["%I:%M:%S %p", "%H:%M:%S"]` | `["%I:%M %p", "%H:%M"]` | `01:45 PM` | `["%I:%M:%S %p", "%H:%M:%S", "%I:%M %p", "%H:%M"]` | `01:45:00 PM` |
| en_GB | `%T` | `["%H:%M:%S"]` | `["%H:%M"]` | `13:45` | `["%H:%M:%S", "%H:%M"]` | `13:45:00` |
| fi_FI | `%H.%M.%S` | `["%H.%M.%S", "%H:%M:%S"]` | `["%H.%M", "%H:%M"]` | `13.45` | `["%H.%M.%S", "%H:%M:%S", "%H.%M", "%H:%M"]` | `13.45.00` |
| C | `%H:%M:%S` | `["%H:%M:%S"]` | `["%H:%M"]` | `13:45` | `["%H:%M:%S", "%H:%M"]` | `13:45:00` |

The default column is exactly the list this note carried before the relocation,
which is the check that the move is behavior-preserving for the default.
`Locale::ISO` becomes `["%H:%M:%S"]` for the same reason — ISO 8601 permits both,
so the member holds the fuller one and the field's default reduces it, rather
than the member pre-deciding a UI question.

**The strip rule, stated because it meets app-supplied patterns via
`screen.locale=`.** Drop `%S` and the literal run immediately preceding it
(`%I:%M:%S %p` → `%I:%M %p`, `%H%M%S` → `%H%M`). A format with no `%S` is already
minute precision and passes through unchanged. Going the other way, `step < 60`
over a locale whose `t_fmt` carries no seconds falls back to the ISO `%H:%M:%S`
rather than splicing a separator it would have to invent. Both directions want a
spec; the corpus above is small enough to enumerate.

So the expansion table is needed at the boundary anyway (`%T` → `%H:%M:%S`,
`%R` → `%H:%M`, `%r` → `%I:%M:%S %p`) — **verified** as the honest reason to
have one: it is not just tidiness, it is what lets the placeholder derive. That
expansion *stays* at the boundary when the strip moves; it is a representation
change, which is what `D_locale`'s normalize-at-the-boundary rule is about. Note
`t_fmt_ampm` is **not** read: en_GB's is `%l:%M:%S %P %Z`, which carries a zone
name and a blank-padded 12-hour hour, i.e. two directives this field rejects.

### The precedent: minute precision nearly everywhere

**Surveyed 2026-09-05** against each toolkit's own docs or source. The question
was two-part — what precision does a time field *ship* with, and how does an app
ask for seconds.

| Toolkit | Default precision | Seconds | Knob |
|---|---|---|---|
| Vaadin `TimePicker` | `hh:mm` | yes | `step` (`Duration`), default 1 hour |
| HTML `<input type="time">` | `hh:mm` | yes | `step`, default `60` |
| MUI X `TimePicker` | hours + minutes (+ meridiem) | yes | `views:` array |
| Qt `QTimeEdit` | locale **ShortFormat** (en_US `h:mm AP`) | yes | `displayFormat` string |
| Flutter `showTimePicker` | hour + minute | **none** — `TimeOfDay` has no field for them | — |
| Taiga UI `InputTime` | `mode` enum, `HH:MM` … `HH:MM:SS.MSS` | yes | `mode` |
| WinForms `DateTimePicker` | OS **long time**, `h:mm:ss tt` | shipped | `CustomFormat`, to *remove* them |
| Ant Design `TimePicker` | `HH:mm:ss` | shipped | `format` string |

Six of eight default to minutes, which is the shipped default this note picks.
The tally is not the useful half, though — **which two dissent, and why** is:
WinForms inherits the OS *long time* pattern, and Ant Design simply picked a
format. Both are the `t_fmt` failure argued above, observed in the field rather
than predicted here — a clock-display format used as a form-field format, putting
`:00` in front of every user who never asked for it. `D_time_field` should cite
them as evidence for the strip, not as toolkits to follow.

**Qt is the precedent for the detection rule, and how it gets there is the part
worth keeping.** `QDateTimeEdit` seeds itself with
`loc.timeFormat(QLocale::ShortFormat)` — the locale's spelling with the seconds
already gone (en_US short is `h:mm AP`; its long is `h:mm:ss AP t`). That is
exactly "keep the spelling, drop the precision", arrived at independently. Qt
gets it for free because CLDR ships short/medium/long time patterns as separate
data; glibc ships one `t_fmt`, seconds included, with no short variant to ask
for. So the strip specified above is not Tuile working *around* the locale — it
is Tuile computing by hand the datum CLDR would have handed it, landing on the
same answer as the toolkit in this survey with the best locale story.

**Two schools on the knob — and the split has a cause, which is the finding.**
Precision is either a property of the *format string* (Qt, Ant Design, WinForms)
or a *selector orthogonal to spelling* (Vaadin/HTML `step`, MUI `views`, Taiga
`mode`). The correlation is exact, and it runs the other way from a style
preference: **every toolkit that fuses precision into `step` is one where the app
cannot write a format at all.** Vaadin's `TimePicker` Java API has no format
setter — `setLocale()` and `setStep()`, nothing else (**surveyed**); HTML's
`<input type="time">` has no `format` attribute. With the pattern locale-derived
and unwritable, `step` is the *only* precision lever those APIs have. Every
toolkit that does expose a format string leaves `step` alone. Zero exceptions
either way.

So the fusion is not a school anyone joined; it is what falls out of *not having*
a format writer. Which is exactly why Tuile can adopt it cleanly: the ruling
above removes the writer, so the precondition is *made true* rather than the
workaround imported into an API that would contradict it. The day-one version of
this note tried to have both — a fused `step` **and** `formats=` — and needed a
raise-at-assignment rule to keep them from disagreeing; that rule is preserved
under *Re-grow* for the day the writer returns, and is unnecessary while it is
absent.

**Qt is the other reading of the same table, and the one this field declines.**
Qt has a format writer *and* a locale-derived default, and has the spelling gap
that pairing implies — `setDisplayFormat` replaces the locale's spelling
wholesale — and simply does not solve it. **MUI does**: `TimePicker` ships
`views` *and* `format`, with `format` documented as *"Defaults to localized
format based on the used `views`"* (**surveyed**) — precision a selector, the
localized spelling derived from it, the format string an escape hatch that
overrides both. That is the two-knob shape, and it is the right one **if** a
per-field format writer has to exist. It is the re-grow target below, not v1,
because v1 has no writer to reconcile against and reaches MUI's outcome — the
locale's spelling survives the precision switch — with one knob.

#### Re-grow: if a per-field `formats=` writer ever returns

It may, if a real per-field spelling need appears (cost 2 above). When it does,
the field grows MUI's shape, and the interaction rule is already settled:

- **`precision` becomes a stored selector** (`:minutes` / `:seconds`; nil means
  derived from `step`) and `formats=` the override. Precision is a *property of*
  `formats.first` — the opening ruling of this section — so there is only ever
  one authority, and which one depends on whether the derivation ran: `formats`
  nil → `precision` selects the detected form; `formats` set → `precision` reads
  back **derived** from `formats.first` (`%S` present means `:seconds`).
- **Disagreeing explicit values raise at assignment**, either order, naming both.
  Letting `precision` win would silently rewrite a pattern the author wrote
  (the zone directives' *"silently reinterpreted"* class); letting `formats` win
  makes `precision` a silent no-op. There is an author to tell — `D_locale`'s
  asymmetry, *"the probe widens silently (no author to tell), an assignment
  raises (there is one)"* — and `bg_color=`'s eager `KeyError` is the shape.
- **The check keys on `formats.first` alone**, never "any format contains `%S`",
  so a lossy-leniency list `["%H:%M", "%H:%M:%S"]` stays legal beside
  `precision = :minutes`. One `each_directive` pass on the hoisted lexer.
- `precision` must be **stored, never eagerly resolved** into a list — an eager
  one snapshots the session locale, the failure `AGENTS.md` names under Locale.

**The relocation, which does not wait for any of that.** Step-derived precision
needs the *unstripped* form to derive the seconds list from, so the seconds
strip cannot live at the `Locale` boundary as an earlier draft of §"Locale grows
its ninth member" had it. It lives in `TimeField`. Two reasons, and the second
stands even if no field ever asked:

- **The strip is policy, not normalization.** `D_locale`'s boundary rule covers
  the `%T` → `%H:%M:%S` expansion (a representation change) and `first_weekday`'s
  renumbering. "Default to minutes" is a *form field's* ruling, and `Locale`
  holds conventions, not UI defaults — its own stated gate.
- **It is lossy where the other normalizations are not.** A status-bar clock, a
  log timestamp, any consumer rendering a *time display* legitimately wants
  `t_fmt` with its seconds. Strip at the boundary and none of them can recover
  it; they hardcode a separator and take the same regression one layer down,
  with no knob to fix it.

So `Locale#time_formats` carries the locale's spelling at **full detected
precision** (fi_FI `["%H.%M.%S", "%H:%M:%S"]`), the expansion table still runs at
the boundary, and `TimeField` applies default-to-minutes itself. The detected
list table above and `Locale::ISO` are written that way.

### The round-trip reference is a `Time`, and every property is load-bearing

With no per-field writer, this validator has two call sites and both are on
`Locale`: the `time_formats:` assignment (an author to tell — it raises) and the
`t_fmt` probe (nobody to tell — a failing format is dropped and the list falls
back to ISO). Same asymmetry as `date_formats`. The field itself never validates
a format, because every list it holds came through one of those two gates.

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

**Verify before building, ruled either way:** whether
`Date._strptime("1:45pm", "%I:%M %p")` matches — i.e. how strict strptime is
about the literal space and the case of `%p`, and so whether `1:45pm`, `1:45 PM`
and `1:45PM` all parse under en_US. If it is strict, **accept the cost** rather
than derive a spaceless secondary: that is grammar surgery on the locale's
pattern (the same operation the strip rule is kept deliberately minimal about),
and the ISO `%H:%M` secondary means `13:45` always works. One documented
sentence, in the same paragraph as the `%p` limitation.

## `Locale` grows its ninth member

`locale.rb`'s rdoc says *"That is the rule a ninth member has to pass"*, and
`time_formats` passes it cleanly: it is how a value is rendered and parsed, and
it is no part of prose. Concretely:

- `Locale#time_formats`, validated like `date_formats`, carrying the locale's
  spelling at **full detected precision**; `Locale::ISO` gets `["%H:%M:%S"]`.
  ISO 8601 permits reduced accuracy `hh:mm`, so both are legal and the member
  holds the fuller one — the reduction to `hh:mm` is the *field's* default, not
  the locale's, and a clock-display consumer needs the seconds this member is
  the only place to get.
- **No rule that an entry must carry `%S`.** `Locale.new(time_formats: ["%H:%M"])`
  is legal; the field's `step < 60` case over it falls back to ISO `%H:%M:%S` per
  the strip rule, so a validation here would only duplicate that fallback with a
  raise. The validator checks what it checks for `date_formats` — round-trip
  against `REF`, the by-name rejections — and nothing about precision.
- `KEYWORDS` gains `t_fmt`. **Not** `t_fmt_ampm` and **not** `am_pm`, per above.
- `Locale.system`'s existing `LC_TIME` gate covers it — no new category.
- Detection normalizes at the boundary — **expand only**, exactly as
  `first_weekday` and `widen` already do. The seconds strip is *not* a
  normalization and does **not** run here; it is a UI default, it is lossy, and
  it lives in `TimeField`. That line is the one thing to get right in this
  section: `%T` → `%H:%M:%S` is a representation change and belongs at the
  boundary; `%H:%M:%S` → `%H:%M` is a policy that discards information, and a
  boundary that applies it makes the discarded half unrecoverable for every
  other consumer.
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
`TimeFormats::HINTS` = `%H`/`%I`/`%k`/`%l` → `hh`, `%M` → `mm`, `%S` → `ss`,
`%p` → `AM`, `%P` → `am`, `%%` → `%`. The blank-padded `%k` and `%l` are in the
table because both pass the round-trip (`%l` with a `%p`), and a directive that
passes but has no hint makes the placeholder "not at all" for no reason. `%p` is admissible where `%b` was not:
`mmm` would be an invented token, while `AM` is literally what the field prints,
and a placeholder is a typing *sample*. So en_US's derived hint is `hh:mm AM`
and fi_FI's is `hh.mm`.

## Phase 2, and the composite

A **picker dropdown is cheap here**, unlike `DateField`'s calendar grid: a list
of times at a step interval is a `ListDropdown` of strings driven the way
`Select` drives one, with no new machinery and no Popover extraction. Still not
v1 — v1 is manual entry, as `DateField`'s was — but it is a much shorter
follow-up, and `step` is already there to space its rows. Two things the picker
will want to re-argue rather than inherit: Vaadin's divisor rule (a row grid
needs it, the arrow keys don't) and Vaadin's *"no overlay below 900 seconds"*
density cap, which is a picker concern and must not feed back into the
`step < 60` precision rule.

Building this also gives `ideas/composite-field.md` its real consumer:
`DateTimeField` over a `DateField` plus a `TimeField` is the shape that note was
filed for, and it is still blocked on the question that note leaves open (which
component wears a *combination* error), not on this one.

## What shipping owes, beyond the code

The four registrations `AGENTS.md` names — rdoc, the CHANGELOG, the layout list,
the README row — plus this field's own extras: rdoc on
the class; a `D_time_field` entry in `DECISIONS.md` (with the value-type
argument above as its spine, the precedent survey as the evidence for the
precision ruling — a survey table is `DECISIONS.md`'s to own per `AGENTS.md`,
never `COMPARISON.md`'s — and a pointer from `D_date_field`); a CHANGELOG
`Add` line (plus the `Breaking:` line for the lexer hoist, and an `Add` for
`Locale#time_formats`); a `README.md` Components row; the `AGENTS.md` layout
list; book ch7 beside `DateField` and a ch10 mention for `time_formats`; a
`spec/tuile/component/time_field_spec.rb` mirror; a sampler pane under
Input → Typed; and a regenerated `sig/tuile.rbs`.

`step` being the precision knob adds to that list rather than changing its
shape: rdoc on `step=` that states the `< 60` rule and the two named costs, and
on `formats` as a *report* with deliberately no writer (the `Component#size`
wording); the strip and seconds-fallback rules in the spec mirror, plus one
example pinning that `formats` follows a `screen.locale=` reassignment; a ch10
sentence on why the seconds strip is the field's and not the locale's; and a
sampler pane showing the field at both strides under a non-colon locale, since
the whole point is that the locale's spelling survives the switch. **The pane
must supply that locale itself** — it assigns a canned fi_FI-shaped `Locale`
(built with `Locale.from_keywords`, the same route the specs use) to its screen
and shows `step: 60` and `step: 1` side by side; left to the host's locale, the
pane demonstrates nothing on an en_US box.

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
