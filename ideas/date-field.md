# DateField

**Status:** filed 2026-09-03 as a don't-forget list; **2026-09-04 the value
type, the name and the parsing substrate are settled** (below) and a v1 is
scoped — manual entry only, no calendar popup. Everything under *Steal from
Vaadin* and *Handed to this note by others* is still undesigned.

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
- **Reject leftover.** `Date.strptime("2026-09-04junk", "%Y-%m-%d")` *succeeds*,
  silently ignoring the tail. Parse through `Date._strptime` and treat a
  non-empty `:leftover` as no match, or `"2026-09-04junk"` is a value instead of
  bad input.
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
hint), and because formats are strftime, the placeholder is **not** derivable
from the primary format for free — a `"%d.%m.%Y"` → `"dd.mm.yyyy"` mapping table
is a second grammar that will drift. Give `DateField` an explicit placeholder
string with a sensible default rather than deriving one.

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

## Handed to this note by others

- **From the bad-input note's retired `D_date_format`** — what the field accepts is
  this component's call (and, per above, ultimately the app's), and it is
  coupled to the bad-input channel in one direction: **the format choice sets
  the size of the bad-input residue.** ISO-only makes `1.5.2026` bad input; a
  multi-format list makes it a value. So leniency is a *UX* argument, not just
  a parsing one — every format added is a class of bad input that stops
  happening. Three things that follow, none of them designed here:
  - **The default matters more than the knob**, because most apps won't touch
    it. A lenient default buys the residue reduction for free; but the *first*
    entry is also what users see written back, so an ISO-first default is the
    culture-neutral, sortable, screenshot-stable choice — leniency in what
    follows it, strictness in what it emits.
  - **An app-global default plus a per-instance override has a house pattern**
    — `ThemeDef.default` and `VerticalScrollBar.handle_char` / `.track_char`
    are both reassignable app-globals, and AGENTS.md carries the warning that
    comes with them: a spec that reassigns one must restore it, or every later
    example in the run reads the leaked value.
  - **Env auto-detection must not move the *display* format silently.**
    `ColorDepth.detect` (`COLORTERM`, `TUILE_COLOR_DEPTH`) and
    `TerminalBackground.detect` (`COLORFGBG`) are the house pattern for probing
    — probe, let an explicit setting override, detect once at construction —
    but note both are *pinned* in `FakeScreen` for determinism. A detected
    primary format would otherwise make painted-buffer assertions depend on the
    developer's `LC_TIME`, which is exactly the trap AGENTS.md's PTY
    colour-depth note describes. Detect the *parsing* leniency if anything;
    keep what the field writes back fixed unless told otherwise.
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

## Related

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
the converter stays private), `D_select` / `D_menu_bar` (`ListDropdown#anchor_to`
and `anchor_beside` — what a calendar popup would be placed with),
`D_confirm_window` (the modal-commit option's vehicle).
