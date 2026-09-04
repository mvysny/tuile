# DateField

**Status:** filed 2026-09-03 as a don't-forget list; **2026-09-04 the value
type, the name, the parsing substrate and the format/placeholder API are
settled** (below) and a v1 is scoped — manual entry only, no calendar popup.
The locale question the note kept circling was **spun off to
`ideas/locale.md`**, which v1 does not wait for: it ships a stopgap ISO default
instead. The four remaining rulings — canonicalize-on-blur (and on Enter),
Up/Down, no input filter, `%y` plus the calendar — were settled the same day and
have their own section; **v1 is designed end to end.** One thing blocks
implementation: the blur ruling has nowhere to live, because a composed field's
face never receives the blur. That is the *composed-field base* question under
*Still open*, and it wants a session of its own first — it is a question about
five components, not about this one.

`DateField` was Tier 2 in `ideas/new-components.md`, blocked there on a
calendar-grid popup over the (still unextracted) Popover — **the v1 unblocks
itself by dropping the popup**, so it moved to Tier 1 and the grid stayed in
Tier 2 as an additive phase 2. It is also the component
that forced the bad-input channel into existence: a date is the first Tuile
value whose input cannot be constrained keystroke-by-keystroke. That channel has
since shipped as `Component::HasBadInput` (`D_bad_input`), so a date field
inherits it rather than inventing one.

## Settled 2026-09-04

**The value is Ruby's stdlib `Date`.** The `LocalDate` instinct is right about
the semantics and does not transfer: `LocalDate` exists in Java only because
`java.util.Date` was a misnamed instant, and Ruby has no such wart — `Date` *is*
the civil date (no time, no zone, `Date.new(2026, 9, 4).to_s == "2026-09-04"`),
while `DateTime` / `Time` are the ones carrying time and offset. A Tuile-owned
value type would also be one no app's model objects, ORM columns or serializers
speak, and Tuile's job is to edit the app's values, not to introduce its own —
the same rule that makes `ComboBox#value` the item and `IntegerField#value` an
`Integer`.

**So the component is `DateField`, not `DatePicker`.** `D_float_field`'s naming
rule is "named after the Ruby class of its value", which is exactly why
`FloatField` beat `NumberField` — Vaadin's name names the *widget category*, not
the value. Doubly right for a v1 that contains no picker; a later calendar popup
is a feature of the field, not a rename.

Consequences that follow, verified against Ruby 3.3:

- **`require "date"` is needed** — `Date` is not preloaded. Unlike `bigdecimal`
  it is a default gem, always present and never optional, so it is hoisted into
  `lib/tuile.rb` beside `logger` / `strscan`. It gets none of
  `D_bigdecimal_field`'s lazy-load treatment, and citing that precedent for it
  would be a misreading.
- **Formats are strftime directives (`"%d.%m.%Y"`), not Java patterns
  (`"dd.MM.yyyy"`).** `strptime` and `strftime` speak the same vocabulary, so
  the lenient-parse / strict-write asymmetry below costs one array; translating
  Java patterns would be a second grammar to own and keep correct.
- **Parse with `Date.strptime`, never `Date.parse`.** `Date.parse("4 sep")`
  cheerfully returns a date — heuristic guessing that would make the format list
  decorative.
- **A match is *two* gates, not one.** First, reject leftover:
  `Date.strptime("2026-09-04junk", "%Y-%m-%d")` *succeeds*, silently ignoring
  the tail, so parse through `Date._strptime` and treat a non-empty `:leftover`
  as no match. Second — and this is the one the first draft of this note
  missed — **`_strptime` does not check the calendar**:
  `Date._strptime("2026-02-30", "%Y-%m-%d")` hands back
  `{year: 2026, mon: 2, mday: 30}` quite happily, and only constructing the
  `Date` raises `Date::Error: invalid date`. So the recipe is `_strptime` for
  the leftover check, *then* build the `Date` and rescue. Two smaller findings
  from the same probe, both benign: `"2026-9-4"` parses under `"%Y-%m-%d"`
  (strptime does not require zero-padding — free leniency, and an argument for
  canonicalizing on commit), and leading whitespace is *not* skipped.
- **`%y` is answered for free, so decline the `referenceDate`.** Ruby's `%y`
  uses the fixed POSIX window: `62`→2062, `69`→1969. Document that window, or
  don't ship `%y` — Vaadin's centred-on-today window would mean parsing the year
  by hand.
- **`value=` stays untyped, and the truncation is ruled in rdoc.** House style
  is a thin setter (`IntegerField#value=` just calls `to_s`), but `DateTime <
  Date` is true and `Time#strftime` exists, so `field.value = Time.now` "works",
  formats as the civil date, and reads back a `Date`. Keep the thinness and say
  so in one line rather than adding a runtime guard: it is the same
  lenient-in / strict-out shape as the format list itself.

**The placeholder is a `TextField` feature, not a `DateField` trick.** An empty
date field must say which of its formats it writes back, since that is available
nowhere else — but the affordance is general, so it was spun off and has since shipped
(`D_placeholder`). Two findings from there that bind this note:
it **cannot** be implemented through the `display_text` seam (that contract is
one display character per `text` character, so the caret would park past the
hint), and because formats are strftime, the hint is not derivable from the
primary format *for free* — a `"%d.%m.%Y"` → `"dd.mm.yyyy"` mapping table looks
like a second grammar that will drift.

**That refusal has since been lifted, under one condition** — see the next
section. The drift argument holds only while the table is a pretty-printer
bolted on *beside* the format list. Make the table and the format **validator**
the same enumeration and there is one list consulted twice: a directive cannot
enter `formats=` without being in the table, because the validator is what
rejects it. Since the list has to be validated anyway, the humanizer is free.

## Steal from Vaadin: several accepted formats, one used to write back

The mechanism to copy, verified against v25.2
(`components/date-picker/date-formats-flow.md`):

```java
i18n.setDateFormats("yyyy-MM-dd", "MM/dd/yyyy", "dd.MM.yyyy");
```

> Date is always displayed using the primary format `yyyy-MM-dd`. When parsing
> user input, the date picker first attempts to match the input with the
> primary format `yyyy-MM-dd`, then `MM/dd/yyyy`, and finally `dd.MM.yyyy`.

So: **a list of formats; parsing tries them in order and first match wins; the
first one is also the one used to format a value back into input.** That single
asymmetry is the good idea — it makes a field lenient about what it accepts and
strict about what it shows, with no mode flag and no ambiguity about which
format "the" format is. `setDateFormat` (singular) is the one-format shorthand.

**And the list is the leniency knob, so it belongs to the app, not to the
component.** That is the second half of the idea: the same mechanism that makes
a field lenient makes leniency *configurable* without a second concept — one
format is strict ISO, three formats accept what a European or an American
types, and nothing about the field changes but the array. So a `DateField`
exposes the formats per instance (an app editing log timestamps wants exactly
`yyyy-MM-dd`; a data-entry form wants all three), rather than the component
picking one policy for everyone. Note this is *not* the `converter=` strategy
`D_integer_field` refused — a format list configures the field's own
parse/format pair, it does not replace it with an injected one.

Two more worth catching while the page is open:

- **Two-digit years need a `referenceDate`.** `dd.MM.yy` cannot tell 1962 from
  2062, so Vaadin interprets a 2-digit year inside a 100-year window centred on
  a reference date that defaults to today. Steal it or decline it explicitly —
  the trap is shipping `yy` support with no ruling at all. *(Answered above:
  decline it. Ruby's `%y` has its own fixed 1969–2068 window, so the ruling is
  to document that or to drop `%y`.)*
- **Vaadin's own docs advise *against* leaning on the locale.** Locale-derived
  formatting "depends on the specific browser implementation… might not be
  reliable when expecting a specific pattern", and they point at explicit
  formats for finer control. That is direct evidence for explicit formats over
  inference — worth weighing against the env-detection idea below, which is the
  same temptation wearing `LC_TIME`.

## The formats and the placeholder — settled 2026-09-04

### The default is ISO, and it is deliberately a stopgap

```ruby
DateField.default_format = "%Y-%m-%d"   # a String, in strftime; app-global
```

A class-level accessor holding **one** format String. Every `DateField`
auto-populates its `formats` from it **at construction**, and any instance can
override with `formats=` afterwards — so the global is a *seed*, exactly as
`ThemeDef.default` seeds new screens rather than being read live. Two
consequences: an app sets it before building its UI (a later change does not
reach fields already constructed), and `formats` is therefore never nil, which
is what makes the derived placeholder below always well-defined.

Its rdoc says **"may change in the future"**, because this is a stopgap for
`ideas/locale.md` — the seam that eventually owns this value along with the
decimal separator and the calendar grid's month names. Keeping the stopgap to
one String rather than an Array is deliberate: the smaller the surface, the
smaller the later deletion. The cost, accepted: until `Locale` lands, an
app-wide *lenient list* is not expressible globally, only per instance.

**ISO is the default, and not merely as taste.** A lenient default list cannot
be shipped, because `%m/%d/%Y` and `%d/%m/%Y` both match `04/09/2026` and
disagree about what it means — and **no validator can detect that**, since only
the app knows which reading was intended. Shipping the ambiguous pair would be
Tuile guessing on the app's behalf and silently producing April 9 for a European
who typed 4 September: a *wrong value that saves cleanly*, which is strictly
worse than bad input, because bad input is visible. So: **the order of the list
is the disambiguation, and it is the app's call.** Tuile ships the
culture-neutral, sortable, screenshot-stable one and lets the app shoot itself
in the foot deliberately. (Vaadin's three-format example is *app* code, not its
default — no contradiction with stealing the mechanism.)

### `formats=`

Takes a String or an Array of Strings; the reader always returns the frozen
Array, so the writer is polymorphic without the reader going soft. It
dup-and-freezes, or `field.formats << "%q"` walks straight past the validator
and the humanizer. (This is also what finally retires the singular `format=`
shorthand: a writer with no matching reader is a smell, and `formats = "%d.%m.%Y"`
is the shorthand.)

Raises on: `nil`, a non-Array/non-String, an empty Array, a non-String element,
and two content rules:

- **Round-trip.** `Date.strptime(ref.strftime(f), f) == ref`. Three lines, and
  it does four jobs at assignment instead of at the first keystroke — verified,
  not predicted, with `ref = Date.new(1962, 9, 4)`:

  | format | round-trips | what it catches |
  |---|---|---|
  | `"%Y-%m-%d"`, `"%d.%m.%Y"` | ok | — |
  | `"%Y-%m-%D"` | REJECT | `%D` is a whole `mm/dd/yy` — a typo for `%d` |
  | `"%Y-%m"` | REJECT | partial format, silently fills `mday: 1` |
  | `"%d/%m/%y"` | REJECT | `%y` as a **primary** (see the `%y` ruling below) |
  | `"%B %-d, %Y"` | REJECT | `%-d` is strftime-only; `strptime` cannot read it |

  **Every property of the reference date is load-bearing:** *pre-1969* so `%y`
  fails (that is the whole `%y` ruling, for free), *post-1582-10-15* so the
  Gregorian reform does not fail an innocent format, and *month ≠ day* so a
  `%m`/`%d` swap is not masked. It does **not** catch an order *ambiguity*
  (`"%m/%d/%Y"` round-trips itself perfectly) — correct, since which reading was
  meant is the app's call, not something a validator can know.

  The one thing it forbids is a deliberately incomplete parse-only format like
  `"%d/%m"` meaning "this year" — which is `Date.parse`-flavoured guessing, and
  the rejection is a feature.
- **`%x` / `%X` / `%c` are rejected explicitly**, with a message saying Ruby's
  `%x` is not locale-aware. They *look* like a locale channel and are not:
  `strftime("%x")` is a fixed `"09/04/26"` under every locale, and `strptime`
  accepts it — so `%x` would pass the round-trip check while silently meaning
  "American" (`ideas/locale.md` has the receipts).

**A `formats=` landing on a non-empty buffer leaves the buffer alone.** No
reformat, no clear: it is text, it reparses under the new list on the next read,
and if it has gone bad the red well says so. Consistent with "the buffer is the
single source of truth" (`D_integer_field`).

### The placeholder is derived from the primary format

Humanizer table, v1 — **four directives**: `%Y`→`yyyy`, `%y`→`yy`, `%m`→`mm`,
`%d`→`dd`, plus `%%`→`%`; literals pass through. Deliberately no `%b`/`%B`: a
month *name* would force inventing `mmm`/`month`, and typing month names into a
TUI form is rare enough that "set your own placeholder" is the right answer. It
is the obvious first extension if anyone asks.

**And deliberately no `%-m` / `%-d` / `%e`, because the first two cannot be in a
format list at all.** The `-` flag is *strftime-only* — Ruby's `strptime` does
not accept it, so `Date._strptime("4.9.1962", "%-d.%-m.%Y")` is `nil` and the
format is write-only, which is useless for a field that must both parse and
emit. The round-trip validator rejects them unaided (`"%B %-d, %Y"` fails it),
which is the validator doing exactly the job it was added for. `%e` (space-pad)
*does* round-trip, but it is dropped from the table anyway — a hint of `" d"` is
not worth a fifth entry.

**The rule that keeps it honest: derive exactly, or not at all.** If every
directive in the primary format is in the table, the hint is derived; if any is
not, the derived hint is `nil` and the app sets one. Never emit a
half-translated hint with a raw `%q` in it. That is what makes "the hint cannot
lie about the format" a guarantee rather than a hope — and it is the answer to
the original objection, since the format list and the table are validated
together.

Three states, and the spelling:

```ruby
def placeholder = content.placeholder            # the *effective* hint

# nil restores the derived hint; "" suppresses it entirely.
def placeholder=(text)
  @placeholder_override = text                   # the mixin's type rules still apply
  sync_placeholder
end

private def sync_placeholder
  content.placeholder = @placeholder_override || humanize(formats.first)
end
```

`formats=` calls `sync_placeholder` too — that is the whole "hint follows
format" behaviour. `""` suppresses for free, since it is truthy in Ruby and an
empty hint paints nothing. Two things the rdoc owes: `field.placeholder` on an
untouched `DateField` returns `"yyyy-mm-dd"` rather than `nil`, an asymmetry
with `IntegerField#placeholder` and the more useful reading (it answers "what
does this field show?"); and the composed-field rule is still satisfied, because
the storage that matters lives on the leaf `TextField` — `DateField` holds the
*override*, not a second copy of the hint (`D_placeholder`).

**The placeholder is load-bearing, not decorative**, and this is why:
`HasBadInput` mandates one frozen constant with no interpolation, so the message
is `"not a valid date"` and can *never* name the accepted formats. The
placeholder is the only channel that tells the user what to type — a second vote
against ever shipping a hint that can go stale.

## Handed to this note by others

- **From the bad-input note's retired `D_date_format`** — what the field accepts is
  this component's call (and, per above, ultimately the app's), and it is
  coupled to the bad-input channel in one direction: **the format choice sets
  the size of the bad-input residue.** ISO-only makes `1.5.2026` bad input; a
  multi-format list makes it a value. So leniency is a *UX* argument, not just
  a parsing one — every format added is a class of bad input that stops
  happening. Three things that follow, none of them designed here:
  All three of the things that followed are now **answered** above or spun off,
  but the reasoning is worth keeping since it is what produced the answers:
  - **The default matters more than the knob**, because most apps won't touch
    it. A lenient default buys the residue reduction for free; but the *first*
    entry is also what users see written back, so an ISO-first default is the
    culture-neutral, sortable, screenshot-stable choice — leniency in what
    follows it, strictness in what it emits. *(Answered: ISO **only**, not
    merely ISO-first — a lenient default list cannot be disambiguated by any
    validator, so it would trade visible bad input for a silently wrong value.)*
  - **An app-global default plus a per-instance override has a house pattern**
    — `ThemeDef.default` and `VerticalScrollBar.handle_char` / `.track_char`
    are both reassignable app-globals, and AGENTS.md carries the warning that
    comes with them: a spec that reassigns one must restore it, or every later
    example in the run reads the leaked value. *(Answered:
    `DateField.default_format`, seeding each field at construction. The
    spec-restore warning applies to it in full — and moving the value onto
    `Screen#locale` is precisely how `ideas/locale.md` proposes to retire it.)*
  - **Env auto-detection must not move the *display* format silently.**
    `ColorDepth.detect` and `TerminalBackground.detect` are the house pattern
    for probing — probe, let an explicit setting override, detect once at
    construction — but both are *pinned* in `FakeScreen` for determinism, or
    painted-buffer assertions would depend on the developer's `LC_TIME`.
    *(**Spun off to `ideas/locale.md`, and its conclusion reversed there.** The
    determinism worry is real and the `FakeScreen` pin answers it; but a user
    who sets `LC_TIME` does so precisely to change what they *see*, so
    detecting only the parse leniency gives them nothing. Ruby exposes no
    locale data at all, so the whole question turns on whether Tuile may shell
    out to `locale(1)` — which is that note's open decision, and not something
    v1 waits for.)*
- **From the bad-input note's retired option survey** — two designs that make bad input
  *impossible* rather than reportable, both cheaper than they look and both
  with a real cost: a **calendar-grid-only** picker (no text input, so no parse
  at all; ~30 keystrokes for a birth date), and **text input behind a modal
  commit** (a `ConfirmWindow`-shaped dialog that won't close on garbage; heavy
  in a form with six dates). A multi-format parse weakens the case for both,
  which is why they are recorded here rather than settled there.
- **From the bad-input note's retired residue analysis** — a mask (`dd/mm/yyyy` with per-field
  ranges) *is* a format declaration by another route, and it manufactures a
  third state: `"__/05/2026"` is neither garbage nor a value but
  **incomplete**.
  Vaadin models that separately (`setIncompleteInputErrorMessage`). If this
  component grows a mask, it owes a ruling on whether incomplete is bad input
  or its own thing.
- **Settled elsewhere, so not this component's call:** whether the field paints
  anything when its input is bad. `D_has_validation` answered it for every
  field at once — the invalid *well* ORs `bad_input?` through `error_ink?`, so a
  date field reddens on its own with no paint code, and a mask's third state
  (**incomplete**, above) would ride the same hook if it decides to.

## The four remaining rulings — settled 2026-09-04

### 1. Canonicalize on blur, and blur is the settling point

**Yes to both.** On blur, a buffer that parses is rewritten in the primary
format: type `4.9.2026` into an ISO field, Tab away, see `2026-09-04`. The UX
argument is the decisive one — *the user sees that the component understood
what they typed* — and it is what makes the multi-format list legible rather
than mysterious. This is the divergence from `IntegerField`, which deliberately
leaves `"007"` alone: a multi-format list is a statement that input and display
are *separate vocabularies*, which `IntegerField` never claimed. `D_float_field`
had already parked normalization at "a commit point", and `D_on_blur` is it.

And blur is therefore **the first consumer of the settling rule `D_bad_input`
left owed** — the continuous red well settles here, which is what stops `2`,
`20`, `202` reddening on the way to a correct `2026-09-04`.

**Enter commits too.** A form whose default button is reached by Enter never
moves focus, so blur alone would let it save an uncanonicalized buffer — the
gesture is a commit, and the field must treat it as one. `DateField` already
forwards `on_enter`, so it canonicalizes before calling it. (Two gestures, not a
general "commit" notion: that would be scope, and there is no third candidate.)

Five consequences, none of them obvious from the ruling itself:

- **Bad input is left exactly as typed.** Canonicalization is for buffers that
  *parse*; a buffer that does not is untouched, because the user has to see what
  they wrote in order to fix it. Never clear it.
- **It fires no `on_value_change`.** The value did not change, only its
  spelling, and `IntegerField#fire_if_changed`'s value-diff guard already makes
  that automatic — it falls out rather than needing code.
- **Up/Down canonicalize implicitly**, since they go through `value=`, which
  formats with the primary. So Up-then-Down does not return the original text.
  Consistent, worth one rdoc line.
- **The mouse ordering the ruling depends on already holds, and is already
  deliberate.** `Button#handle_mouse` calls `super` — which is where
  `Component#handle_mouse` does `screen.focused = self` — *before*
  `@on_click&.call`, and its rdoc says so: *"`super` runs first, so the click
  also focuses."* `Checkbox` and `Select` are identical. So a user who types a
  bad date and clicks Save blurs first, and the save gate sees a settled field.
  **⚠ But AGENTS.md states this backwards** — *"a widget that resolves clicks
  inside its own rect overrides **without** `super`"*, citing `List` and
  `Select`, both of which call it (`list.rb:322`, `select.rb:174`). Harmless
  drift until now; once blur is a commit point, that sentence is instructions
  for losing a user's edit in the next click-to-act widget someone writes. Fix
  it when this ships.

### 2. Up/Down step a day; an empty field steps to today

`IntegerField` treats an unparseable buffer as `0`, so the analogue is
`Date.today` — Up in an empty field lands on today, which is what a picker would
open on anyway.

### 3. No input filter at all

`DateField` overrides no `insert_text`: **every character is admitted, typed or
pasted, and the residue is reported through `bad_input?`.** The grammar is not
prefix-closed (`"2020-13-45"` is well-formed at every character), which is the
condition `D_input_filters` names for taking the accept-and-report road. The
tempting middle — rejecting characters no configured format can contain — is
refused by the same entry: a partial filter *"reads as a guarantee and isn't"*.
`max_text_length` likewise stays unset rather than capping at the longest
format.

### 4. `%y` parses, never writes back; pre-1969 dates are supported

The field must handle dates a history-quiz app would ask about, so **the primary
format always carries `%Y`** — and that is not a rule anyone has to remember,
because the round-trip validator's pre-1969 reference date rejects `%y` as a
primary automatically. `%y` stays legal in the *parse* positions (typing
`04.09.26` still works), with Ruby's fixed POSIX window documented: `69`→1969,
`26`→2026.

**The trap that actually bites the history use case is the calendar, not the
year width.** Ruby's `Date` defaults to `Date::ITALY` — the Gregorian reform as
adopted in 1582 — so:

```ruby
Date.new(1582, 10, 10)                          # Date::Error: invalid date — those ten days never existed
Date.strptime("1500-01-01", "%Y-%m-%d")         # Julian; nine days off the Gregorian one…
Date.strptime("1500-01-01", "%Y-%m-%d", Date::GREGORIAN)
# …and both print "1500-01-01", so the difference is invisible
```

### The calendar: `Date::GREGORIAN` by default, with a setting

**Tuile does not inherit Ruby's `Date::ITALY` default.** Investigated rather
than assumed, and the evidence runs one way:

- **Ruby core calls it a mistake.** In [bug #18946][b] Matz wrote: *"`to_date`
  has been use GREGORIAN calendar since 2011-05-31 and `to_datetime` preserved
  the old `DEFAULT_SG` (ITALY). I assume this is a mistake and both should use
  GREGORIAN."* The bug is closed with the conversions moved toward Gregorian.
- **`Time` is proleptic Gregorian and always has been**, so the two stdlib
  classes disagree before 1582: `Date.new(1500,1,1).to_time` is `1500-01-10`,
  and `Time.new(1500,1,1).to_date` prints `1499-12-23`. An app that touches both
  gets a nine-day jump.
- **ISO 8601 mandates proleptic Gregorian**, and ISO is this field's *default
  primary format* — so under `ITALY` a `DateField` would emit `"1500-01-01"`
  that is not the ISO 8601 date of that name. Ruby's own `Date#iso8601` has the
  same wart: it prints `"1500-01-01"` for the Julian date, and
  `Date.iso8601("1500-01-01")` reads it back nine days off a Gregorian one.
- **The ten missing days stop being a hole.** Under `GREGORIAN`,
  `1582-10-10` is an ordinary date rather than a `Date::Error` the user cannot
  type their way out of.

So: **`DateField.default_calendar_start = Date::GREGORIAN`**, a class-level seed
read at construction into a per-instance `calendar_start`, exactly symmetric
with `default_format` / `formats` — same seed semantics, same "may change"
rdoc, and the same eventual destination, since ITALY-vs-ENGLAND (1752) is
literally a per-country fact and belongs in `ideas/locale.md` when it lands.

**The cost, stated rather than hidden:** the round-trip is exact only when the
field's calendar matches the calendar of the `Date`s the app hands it, and
`Date.new(1500, 1, 1)` in *app* code is `ITALY` because that is Ruby's default.
So an app that builds pre-1582 dates naively and sets `value=` gets them back
nine days off after a canonicalization. That is what the setting is for, and the
rdoc says so in one line. **Rejected alternative:** having `value=` remember the
incoming `Date`'s own `start` and parse back with it. It makes the round-trip
exact for free, and it is wrong anyway — `value` would stop being a pure
function of the buffer, which is the shape every other typed field has
(`D_integer_field`: "the buffer is the single source of truth"), and a field
typed into from empty would have no `start` to remember.

[b]: https://bugs.ruby-lang.org/issues/18946

## Still open

### The composed-field base — brainstorm this *before* implementing `DateField`

Canonicalize-on-blur has nowhere to live yet. `on_blur` fires on whatever *held*
focus; `HasContent` forwards focus **down**, so the inner `TextField` is what is
focused and the composed `DateField` never sees the blur at all.

**And the fix is not `HasContent`.** That mixin says one thing — *I own exactly
one child directly, named `content`* — and it is included by `Window`, which is
not a field and must not grow a field's forwarding. Blur-forwarding is not a
fact about having one child; it is a fact about being a **face over an inner
editor**, which is a narrower thing that four components already are
(`IntegerField`, `FloatField`, `BigDecimalField`, `ComboBox`) and `DateField`
makes five.

That narrower thing is now designed, as **`Component::AbstractWrappingField`**
in `ideas/composed-field.md` — read that note, not this section, before writing
any `DateField` code. What it carries, all of which every composed field
currently hand-copies:

- the blur (and Enter) commit point, forwarded from the inner field to the face
- `placeholder` / `placeholder=` delegation (`D_placeholder` already mandates
  the pair, and all four write it out longhand)
- `on_enter` forwarding, `cursor_position` delegation
- the `bg_color = BG_INHERIT` + `default_bg_color` well pairing that AGENTS.md
  says a new composed field "owes both or its face paints untinted"
- `tab_stop? = false` (the wrapper is not the stop; its inner field is)

**The tension to resolve, not assume away:** `D_float_field` and `D_select`
both ruled *duplicate rather than DRY a shallow shell*, and explicitly set the
bar at a **fourth** copy before re-arguing. This is that fourth copy — and the
list above is no longer a shallow shell, it is five or six distinct
obligations, one of which (the well pairing) is already documented as a thing
implementors forget. But the counter-argument is on the record too: each of
those items is one or two lines, and a base class is how `AbstractView`
junk-drawers start. Worth a real session, and worth checking whether the answer
is a *mixin carrying the delegations* rather than an abstract class, since
`HasContent` / `HasValue` / `HasPlaceholder` are already the house shape.

### Deferred by choice

- **PageUp/PageDown stepping a month.** Not in v1 — recorded so it is a
  decision rather than an omission.
- **Phase 2, the calendar grid.** Still blocked on the Popover extraction
  (`ideas/new-components.md`); v1 is manual entry only and unblocks itself by
  dropping it.

## Related

`ideas/locale.md` (**the spin-off**: where `DateField.default_format`,
`FloatField`'s decimal comma and the calendar grid's month names all eventually
live — and why Ruby forces the question in the first place),
`D_bad_input` (the shipped channel a date field is the first real consumer of —
and the population test that puts it in),
`D_on_blur` (the commit point a canonicalizing or settling date field would use,
and why the bad-input push notice is still unbuilt),
`D_placeholder` (the empty-buffer hint this field is the first caller for — and
why it is not a `display_text` override),
`ideas/binder.md` (the
four-layer vocabulary —
a date's `input` is the typed glyphs, its `value` a `Date`),
`D_has_validation` (who paints an error: the field paints the well, the
container paints the message), `D_caption_ownership` (a date field carries no
caption either),
`ideas/new-components.md` (Tier 2, and the Popover extraction it lists as the
blocker), `D_integer_field` (the composed-field shape a typed field follows;
the converter stays private), `D_float_field` (the naming rule — a typed field
is named after the Ruby class of its value), `D_input_filters` (why this field
filters *nothing*: its grammar is not prefix-closed, and a partial filter reads
as a guarantee it isn't), `D_select` / `D_menu_bar` (`ListDropdown#anchor_to`
and `anchor_beside` — what a calendar popup would be placed with),
`D_confirm_window` (the modal-commit option's vehicle).
