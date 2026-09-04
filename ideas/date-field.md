# DateField

**Status:** filed 2026-09-03 as a don't-forget list; **2026-09-04 the value
type, the name, the parsing substrate and the format/placeholder API are
settled** (below) and a v1 is scoped — manual entry only, no calendar popup.
The locale question the note kept circling was **spun off to
`ideas/locale.md`**, which v1 does not wait for: it ships a stopgap ISO default
instead. What is still undesigned is listed under *Still open* at the end —
four rulings, of which the blur/canonicalization one is the only hard one.

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

- **Round-trip.** `Date.strptime(ref.strftime(f), f) == ref` for a reference
  date. Three lines, and it catches the whole family of typos and half-formats
  at assignment instead of at the first keystroke: `"%Y-%m-%D"` (`%D` is a whole
  `mm/dd/yy`), and `"%Y-%m"`, which otherwise parses fine and silently fills
  `mday: 1`. That subsumes the partial-format question with no separate ruling.
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

Humanizer table, v1 — **numeric directives only**: `%Y`→`yyyy`, `%y`→`yy`,
`%m`→`mm`, `%d`→`dd`, `%-m`/`%-d`→`m`/`d`, `%%`→`%`, literals pass through.
Deliberately no `%b`/`%B`: a month *name* would force inventing `mmm`/`month`,
and typing month names into a TUI form is rare enough that "set your own
placeholder" is the right answer. It is the obvious first extension if anyone
asks.

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

## Still open

Four rulings v1 owes. Only the first is hard.

- **Is blur the canonicalization point — and is it also the *settling* point for
  the red well?** Two questions that want answering together. Vaadin reformats
  to the primary format on blur, while `IntegerField` deliberately does *not*
  normalize (`"007"` stays `"007"`, and `D_float_field` parked normalization at
  a commit point, which `D_on_blur` has since become). The date case is
  arguably different — a multi-format list is a statement that input and
  display are separate vocabularies, which `IntegerField` never claimed — but
  that is an argument to write down, not to assume. The second half: `D_bad_input`
  records that the settling rule which would soften the *continuous* red well is
  still owed, and a date field is where continuous is worst (`2`, `20`, `202`
  are all red on the way to a correct `2026-09-04`). If blur canonicalizes, blur
  is the obvious settling point and this field is the one that pays for the
  rule. Or it deliberately is not, and the first consumer of the settling rule
  is somebody else.
- **Up/Down are unclaimed.** `IntegerField` steps by one; this note never
  mentioned arrows. Stepping a day is one line and obviously wanted. The
  interesting part is the empty/bad case: `IntegerField` treats an unparseable
  buffer as `0`, so the analogue is `Date.today` — Up in an empty field lands on
  today, which is a genuinely nice affordance and matches what a picker would
  open on. Open: whether bad-but-*non-empty* input also snaps to today
  (destroying what the user typed), and whether PageUp/PageDown step a month
  (instinct: no, scope creep — but say so rather than leaving it).
- **The "no input filter" ruling is implied but never stated.** The grammar is
  not prefix-closed (`"2020-13-45"` is well-formed at every character), so
  `D_input_filters` sends this field down the accept-and-report road. There is a
  tempting middle — reject characters no configured format can contain — and the
  same entry says why not: a partial filter *"reads as a guarantee and isn't"*.
  Write the sentence explicitly (**`DateField` overrides no `insert_text`; every
  character is admitted and the residue is reported**), or the next reader
  re-derives it. Same for `max_text_length`: leave it unset rather than capping
  at the longest format.
- **`%y`: ship with the documented window, or drop it.** Still framed above as
  an unresolved OR. Cheap to settle, and leaning ship-plus-document: rejecting a
  directive Ruby handles fine is more code for less function. Note it interacts
  with the round-trip validator above — `%y` cannot round-trip a pre-1969 date,
  so if the reference date is chosen outside the POSIX window the validator
  rejects `%y` *as a primary* on its own, while leaving it usable in the parse
  positions. That may well be the whole ruling, for free.

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
