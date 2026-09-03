# DatePicker — a holding note

**Status:** filed 2026-09-03 as a **don't-forget list, not a design.** No API
is proposed here and none should be added until the component is actually
picked up; the point is that three other notes handed things to a `DatePicker`
and there was nowhere to put them.

`DatePicker` is Tier 2 in `ideas/new-components.md`, listed as blocked on a
calendar-grid popup over the (still unextracted) Popover. It is also the
component that forced `ideas/bad-input.md` into existence: a date is the first
Tuile value whose input cannot be constrained keystroke-by-keystroke.

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

Two more worth catching while the page is open:

- **Two-digit years need a `referenceDate`.** `dd.MM.yy` cannot tell 1962 from
  2062, so Vaadin interprets a 2-digit year inside a 100-year window centred on
  a reference date that defaults to today. Steal it or decline it explicitly —
  the trap is shipping `yy` support with no ruling at all.
- **Vaadin's own docs advise *against* leaning on the locale.** Locale-derived
  formatting "depends on the specific browser implementation… might not be
  reliable when expecting a specific pattern", and they point at explicit
  formats for finer control. That is direct evidence for explicit formats over
  inference — worth weighing against the env-detection idea below, which is the
  same temptation wearing `LC_TIME`.

## Handed to this note by others

- **From `ideas/bad-input.md` §9 `D_date_format`** — what the field accepts is
  this component's call, and it is coupled to the bad-input channel in one
  direction: **the format choice sets the size of the bad-input residue.**
  ISO-only makes `1.5.2026` bad input; a multi-format list makes it a value. So
  leniency here is a *UX* argument, not just a parsing one — every format added
  is a class of bad input that stops happening. And if formats are
  auto-detected from the environment, `ColorDepth.detect` (`COLORTERM`,
  `TUILE_COLOR_DEPTH`) and `TerminalBackground.detect` (`COLORFGBG`) are the
  house pattern: probe, let an explicit setting override, detect once at
  construction.
- **From `ideas/bad-input.md` §6** — two designs that make bad input
  *impossible* rather than reportable, both cheaper than they look and both
  with a real cost: a **calendar-grid-only** picker (no text input, so no parse
  at all; ~30 keystrokes for a birth date), and **text input behind a modal
  commit** (a `ConfirmWindow`-shaped dialog that won't close on garbage; heavy
  in a form with six dates). A multi-format parse weakens the case for both,
  which is why they are recorded here rather than settled there.
- **From `ideas/bad-input.md` §2** — a mask (`dd/mm/yyyy` with per-field
  ranges) *is* a format declaration by another route, and it manufactures a
  third state: `"__/05/2026"` is neither garbage nor a value but
  **incomplete**.
  Vaadin models that separately (`setIncompleteInputErrorMessage`). If this
  component grows a mask, it owes a ruling on whether incomplete is bad input
  or its own thing.
- **From `ideas/caption-and-error-ownership.md`** — whether the field paints
  anything when its input is bad is *not* this component's call to make alone;
  it inherits whatever that note decides.

## Related

`ideas/bad-input.md` (the channel a date field is the first real consumer of;
§6 options, §9 `D_date_format`), `ideas/binder.md` (the four-layer vocabulary —
a date's `input` is the typed glyphs, its `value` a `Date`),
`ideas/caption-and-error-ownership.md` (who paints an error),
`ideas/new-components.md` (Tier 2, and the Popover extraction it lists as the
blocker), `D_integer_field` (the composed-field shape a typed field follows;
the converter stays private), `D_select` / `D_menu_bar` (`ListDropdown#anchor_to`
and `anchor_beside` — what a calendar popup would be placed with),
`D_confirm_window` (the modal-commit option's vehicle).
