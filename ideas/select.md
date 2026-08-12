# Select — the enum field: a `Label` face over a `ListDropdown`

**Status:** designed 2026-08-12, not built. Supersedes the one-line
"ComboBox − filter" entry in `new-components.md` (Tier 1), whose framing was
wrong in two ways — see *Corrections to the survey line* below. When this is
built, the nuggets split the usual way: the enum-vs-data criterion and the
widget-choice table are **book** material (ch7, next to the other fields); the
"claims no printable keys" rule is an **AGENTS.md** invariant; the criterion
plus the three rejected alternatives become a `D-select` entry in
**DECISIONS.md**.

## What it is

A one-row closed-choice field: a `Label`-style face showing the selected item's
label plus a `▾` affordance, dropping open a `ListDropdown` of the options.
Enter/Down opens, arrows move the highlight, Enter commits, ESC cancels.

Shape follows the established composed-field pattern (`D-integer-field`'s
taxonomy): `Select < Component`, `include HasContent` + `include HasValue`,
holding its face as the content child and owning the `ListDropdown` as an
overlay — i.e. structurally `RadioGroup`'s composition with `ComboBox`'s
overlay. `value` is the **selected item** (any type), `items=` + `item_label`
as on `ComboBox`/`RadioGroup`. All of `D-combobox`'s value rules carry over
unchanged: an index is how a selection is *resolved*, never how it is *stored*;
`items` is chrome and `value` is authoritative and may hold what `items`
doesn't.

**`Select` must declare `tab_stop? = true` itself** — and it's the first
composing wrapper that does, so this needs saying out loud. `ComboBox`,
`IntegerField`, `RadioGroup` and `CheckboxGroup` all leave `tab_stop?` at
`Component`'s `false`, because their inner widget (`AbstractStringField`,
`List`) carries the stop and a tab-stop wrapper around a tab-stop child would
double-stop Tab. Select's content child is a `Label` — inert chrome, neither
focusable nor a tab stop — so if Select doesn't claim the stop, **nothing does
and Tab can never reach it**. The rule's letter reads the other way; its
purpose (exactly one tab stop per widget) is what's being preserved. Pin it
with a spec that Tab lands on a Select exactly once.

## The criterion: enum vs. data, not item count

This is the part worth keeping even if the component is never built.

- **Select is for enums** — labels the *developer* authored: closed set, stable
  order, known when the code is written. Log level, sort order, theme,
  alignment, encoding, line endings, Yes/No/Ask.
- **ComboBox is for data** — items the app supplies at runtime, open-ended,
  labels you don't control. Countries, users, branches, files.

Item count is a *symptom*, not the criterion. A 12-value enum is still a
Select; a three-row country list loaded from a DB is still a ComboBox, because
next release it's 200 rows and the widget choice shouldn't have to change.
"≤ 7 items → Select" was the rule we started with and it's actively harmful —
it invites a three-row country list into a Select, which is how we found the
type-ahead hole below.

The full field-choice table, once Select exists:

| Situation | Widget | Why |
|---|---|---|
| Developer-authored enum, one form row | **Select** | 1 row, borrows *n* transiently |
| Same enum, options deserve side-by-side comparison | `RadioGroup` | spends *n* rows permanently |
| App-supplied / open-ended / unknown labels | `ComboBox` | filtering is the navigation |
| Multi-select over an enum | `CheckboxGroup` | frozen `Set` value |

Select vs. `RadioGroup` is the sharper redundancy question, not Select vs.
ComboBox: `RadioGroup` already composes a `List`, already has cursor +
Space-selects, already has no filtering. The **only** differentiator is
vertical footprint, and on a TTY that's decisive — a settings form with six
enum fields is 6 rows versus ~36.

## It claims no printable keys — the invariant

Enter/Down/arrows/PgUp/PgDn/ESC and mouse. **Nothing else.** Every printable
key bubbles past it, up the focus chain, to the app (key-dispatch rung 3).

That's the one capability unreachable by configuring a `ComboBox`, which eats
all printables unconditionally, and it's worth more than the type-ahead it
replaces. A form's `s`-to-save and a layout's `1`/`2`/`3` pane jumps keep
working while focus sits in a Select. Combined with having no caret — the
strongest affordance a TTY has, not spent promising free-text entry over a
four-value enum — that's the whole case for the component.

## Alternatives rejected

### Prefix type-ahead (single-key)

`g` jumps to the first item starting with `g`. **Rejected: silently wrong.**
With Finland / Fiji / Jamaica, typing `fij` selects *Jamaica* — each key is a
fresh single-char match, so `f`→Finland, `i`→(no match), `j`→Jamaica. The user
types a word and lands somewhere unrelated, with no feedback that anything went
wrong.

### Prefix type-ahead (timed accumulating buffer)

The standard GUI fix — accumulate a prefix, reset it after ~1s of idle (Swing's
`JList`, GTK, Finder, Explorer all do roughly this). **Rejected: it *is* the
ComboBox query, hidden.** A buffer that filters the candidate set is a query
string; hiding it and clearing it on a timer makes it worse, not lighter, and
it reintroduces exactly the second state Select exists to avoid. If you're
holding query state, showing it is strictly better — and showing it is a
ComboBox.

Worse here than in a GUI, and for a TUI-specific reason: the timeout depends on
inter-keystroke timing that a terminal doesn't preserve. AGENTS.md already
documents that bytes arriving in one read burst merge into a single bogus key,
and that a human's millisecond gaps are what keep `Keys.getkey` honest. Over a
laggy SSH link keystrokes arrive bunched; a paste arrives with no gaps at all.
The one signal the buffer relies on is the one signal a TTY degrades.

Note this also retires the "make labels prefix-unique" workaround (`1 -
Finland`, `2 - Fiji`, or info/warn/error): that constraint existed only to
rescue type-ahead. With no type-ahead, labels need no disambiguation at all,
and the component stops being narrow.

### Cycle-in-place (`◂ Dark ▸`, Space/Left/Right, no dropdown)

For 2–4 options: no popup, one row, no transient state. **Rejected 2026-08-12
by MV: you select blindly.** The values you're choosing *between* are never on
screen — you discover them by cycling through them, one at a time, with no way
to see the set or know how many there are. The dropdown is better UX at every
item count, so the `ListDropdown` face is the only face. This also keeps the
vocabulary from growing a fourth closed-choice widget (cf. `D-box-layouts`'
"there is no `Auto`").

*Re-grow rule:* if this ever comes back, it's a **face** on the same component
(a `dropdown: false`-style knob reusing the identical value seam), never a
separate component — and it needs a real argument about visibility, not just a
row-budget one.

### A read-only `TextField` as the face (the survey's framing)

**Rejected:** a read-only `TextField` is still a text field — it carries the
inherent-bg well, the caret machinery, the horizontal scroll window, and it's
an inherent-bg widget that opts out of `bg_color` inheritance. A Select's face
is a label. Building it as a `Label` sidesteps all of it.

## Corrections to the survey line

`new-components.md` Tier 1 says: *"Select | `ComboBox` − filter | ComboBox with
a read-only field; near-free. Deferred once already in `D-combobox` (wants the
parked read-only axis)"*. Both halves are wrong:

1. **It doesn't need the read-only axis.** That's an artifact of assuming a
   `TextField` face. With a `Label` face there's nothing to make read-only, so
   the `D-has-value`-parked forms-layer axis isn't a blocker — nothing gates
   this component.
2. **It isn't "ComboBox − filter."** It's a *second driver* of `ListDropdown`,
   which is precisely what that class was extracted for. Fix the survey row
   when this lands.

## Open questions

- **`ListDropdown`'s class doc assumes a driving text input** ("the dropdown a
  text input drops open… so the caret stays in the driving input"). Select is
  the second driver and has no caret, which is the good news — it proves the
  extraction generalized — but the rdoc needs rewording from "input" to
  "driver". Check whether `Menu#show_cursor_when_inactive` and the
  non-focusable ruling still read correctly when the driver is focusable and
  caretless.
- **Anchoring wants extracting.** `ComboBox#anchor` (private, ~line 259) does
  the below-the-field placement with the flip-above-when-it-would-overrun rule.
  Select needs the identical geometry. That's the "Anchored Popover extraction"
  already listed as infrastructure item 4 in `new-components.md` — Select is a
  second caller for it, so either extract then, or duplicate deliberately per
  the `D-float-field` rule and note it.
- **What does an empty Select show?** `empty?`/`clear` come from `HasValue`;
  `value = nil` presumably renders a blank face plus `▾`. Is a nil value
  legal-and-normal (an optional enum field) or does it want a placeholder
  string? `ComboBox` renders nothing selected — probably just match it.
- **Does Space commit or open?** `Checkbox`/`CheckboxGroup`/`RadioGroup` all
  use Space as the toggle/select gesture, so Space-opens-the-dropdown is the
  consistent read. Worth pinning against book ch5's Enter/Space table so the
  gesture stays one rule across the closed-choice widgets.
- **Should `RadioGroup` and Select share anything?** Almost certainly not —
  same shallow-commonality argument as `D-float-field`. Duplicate the ~15-line
  items/label/select-at shell rather than growing an
  `AbstractClosedChoiceField`.
