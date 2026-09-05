# Components Vaadin has and Tuile doesn't — the survey

**Status:** survey done 2026-07-25 against Vaadin **25.2** (54 free/OSS
components, via the Vaadin docs MCP). This file is the roadmap; each
component we actually decide to build gets its own `ideas/<name>.md`.
Retire this file once the interesting part of the list is either built or
explicitly rejected — the tiering below is the only nugget worth keeping,
and it belongs here, not in a durable doc, because it goes stale as we
build.

Batch 1 ("field components only") is **done** — every idea filed under it has
graduated: `checkbox` (`DECISIONS.md` `D_boolean_fields`) and `checkbox-group`
(`D_checkbox_group`), both built 2026-07-30; `radio-group` (`D_radio_group`),
built 2026-07-31; `progress-bar` (`D_color_slots`, book ch7 "Reporting
progress") and `password-field` (`D_integer_field`'s taxonomy, book ch7
"Editing text"), both built 2026-08-02.

The **box layouts** that headed the gating list below are done too
(`D_box_layouts`, 2026-08-07) — `Layout::Vertical` / `::Horizontal`, plus the
sampler ported onto them.

## What Tuile already has

Seven of the 54 have a counterpart: Button, Text Field, Text Area,
Integer Field, Combo Box (1:1), Dialog ({Tuile::Component::Popup} plus
`Window`/`InfoWindow`/`PickerWindow`), Themable Mixin
({Tuile::Theme}/{Tuile::ThemeDef}). **List Box** is half-there:
{Tuile::Component::List} takes typed items and a renderer since 2026-08-14
(`D_list_items`), but has no multi-select — {Tuile::Component::CheckboxGroup}
is the nearest thing.

Tuile also has pieces Vaadin doesn't name as components — `ListDropdown`,
`TextView`, `LogWindow`, `VerticalScrollBar` — so the gap is not
symmetric.

That leaves ~46 gaps.

## Tier 1 — reachable from what exists (S–M each)

| Component | Builds on | Note |
|---|---|---|
| ~~Box layouts (H/V)~~ | `Layout` | **built** 2026-08-07 (`D_box_layouts`, book ch3); `Vertical`/`Horizontal` over `Box`, additive sugar on top of `Absolute` — no foundation change |
| ~~Checkbox~~ | `HasValue` | **built** 2026-07-30 (`D_boolean_fields`); tri-state still deferred |
| ~~Radio Group~~ | `List` + `HasValue` | **built** 2026-07-31 (`D_radio_group`); composes a `List`, cursor roams and Space selects |
| ~~Checkbox Group~~ | `List` + `HasValue` | **built** 2026-07-30 (`D_checkbox_group`); composes a `List`, frozen `Set` value |
| ~~Select~~ | `ListDropdown` + `HasValue` | **built** 2026-08-12 (`D_select`, book ch7); a *second driver* of `ListDropdown`, not "ComboBox − filter" — it paints its own one-row face and needs no read-only axis. Claims no printable but Space |
| ~~Password Field~~ | `TextField` | **built** 2026-08-02 (`D_integer_field`'s taxonomy — subclass, since a password's value *is* its text; mask default in `D_ambiguous_width`); a `display_text` seam, one mask glyph per character |
| ~~Number Field~~ | `IntegerField` twin | **built** 2026-08-07 as `FloatField` (`D_float_field`) and `BigDecimalField` (`D_bigdecimal_field`, on Tuile's first optional dep); each named for its Ruby value type, deliberate copies of `IntegerField` |
| ~~Progress Bar~~ | `draw_line` + `EventQueue#tick_fps` | **built** 2026-08-02 (`D_progress_bar`, book ch7); a `value` that stays out of `HasValue`, ticker synced from `attached? && indeterminate?` |
| ~~Notification~~ | `Popup` + `Ticker` | **built** 2026-08-17 (`D_notification`, book ch7); one non-modal top-right box, N messages, one 3 s ticker retiring the oldest. Corner anchor is its own `reposition` override, so `Popup` was untouched — and the `Popover` extraction still waits for a second *kind* of anchoring |
| ~~Confirm Dialog~~ | `Popup`+`Window`+`Button` | **built** 2026-08-31 as `ConfirmWindow` (`D_confirm_window`, book ch7); the component is the builder — `#button` plus the `alert`/`confirm`/`yes_no` factories — every button dismisses, MenuBar-shaped mnemonics with `q`/`g`/`G` reserved. The fold-`PickerWindow`-in idea is **rejected**: the two disagree on every semantic that matters (cursor, default, ESC, close-on-pick) and share only API shape |
| Details → Accordion | `HasContent` | Details is the atom, Accordion the group |
| ~~Tabs → TabSheet~~ | plain `Component` + the tree API | **built** 2026-08-23 (`D_tabs`, book ch7); a strip (one tab stop, Left/Right, immediate activation) plus a sheet whose `children` are `[strip, pane]`. Neither is `HasValue` — a tab selection is view state — and neither is `HasContent`; a `TabSheet` hides a pane by *detaching* it, deliberately — that is what fires the lifecycle hooks on every switch, and it stays the choice now that `Component#visible=` exists (`D_visibility`); the strip owns mutable `Tabs::Tab` handles rather than the `items`/`item_label` shell. Hidden/disabled/closeable tabs, lazy panes and a scrolling strip are deferred, each additive (`D_tabs`) |
| Popover | `ListDropdown#anchor_to` (extracted 2026-08-12) | generalize the anchored non-modal overlay: `anchor_to` moves down to it and `ListDropdown` inherits it. Build it when the second *kind* of anchoring appears (a point; a right edge that flips) — not the second caller of the same kind. Nothing gates on it today: Menu Bar shipped without it |
| ~~Menu Bar~~ | `ListDropdown` (+ `anchor_beside`) | **built** 2026-08-24 (`D_menu_bar`, book ch7), mnemonics the same day. Turned out *not* to need the Popover extraction: a focused strip drives a cascade of non-modal `ListDropdown`s the way `Select` drives one, so the additions were a side-anchor method, a highlighted-row rect and a cursor pass-through. Unlimited submenu depth; checkable/disabled items and global-shortcut activation deferred indefinitely |
| ~~DateField~~ | `AbstractWrappingField` + `HasBadInput` | **built** 2026-09-04 (`D_date_field`, book ch7), after re-tiering out of Tier 2 the same day: the v1 is manual entry only, so the calendar popup it was blocked on became a phase 2 (still Tier 2 below). Value is stdlib `Date`; a per-instance list of strftime `formats`, first whole match winning and `formats.first` written back on blur/ENTER. It filters *nothing* — a date's grammar is not prefix-closed, so the residue is reported through `HasBadInput` — and its empty well derives its own `HasPlaceholder` hint from the primary format. `%y` is rejected outright and the calendar is proleptic Gregorian, not Ruby's `Date::ITALY` |
| Slider | `draw_line` | arrows/PgUp; 25.2 also has a two-thumb *range* variant |
| Breadcrumbs | `Label`/`StyledString` | clickable path segments |
| Markdown | `TextView` + `StyledString` | Markdown subset → styled text; high value on a TTY |

## Tier 2 — worth doing, each blocked on a new seam

| Component | Blocked on |
|---|---|
| **Grid** (the flagship gap) | column model + renderer strategies + typed items + horizontal scroll (L) |
| Form Layout | a field label/helper seam (Vaadin's `HasLabel`) — Tuile fields carry no caption by decision (`D_caption_ownership`), so the seam is the layout's own cells: `ideas/form-layout.md` |
| Email Field | nothing, per `D_bad_input` — its value *is* its input, so it has no bad-input state and contributes only a packaged regex; **re-tiered toward reject** |
| Calendar grid for `DateField`, and the Time / DateTime twins | the grid needs the calendar popup over Popover (L). It is **phase 2** of a field that already ships (`D_date_field`, Tier 1 above), so nothing is blocked on it: a `DateField` is fully usable by typing, and the grid is additive — a second way to set the same `value`, placed with `ListDropdown#anchor_to`. Two things it inherits rather than re-decides: the month names it paints are the locale question of `ideas/locale.md`, and `PageUp`/`PageDown` stepping a month is deferred there too. The Time / DateTime twins no longer wait on that seam — it shipped (`D_locale`) — and `TimeField` is settled in `D_time_field` (2026-09-05; build brief in `ideas/time-field.md`): its own picker dropdown is a `ListDropdown` of times spaced by the `step` v1 already ships, so unlike the calendar grid it needs no new machinery |
| Multi Select Combo Box | Checkbox Group + ComboBox |
| Split Layout → Master Detail Layout | mouse **motion/drag**: Tuile runs X10 mode 1000 (press only, no release, no motion) |
| Virtual List | a lazy data-provider strategy on `List` |
| Side Nav | hierarchical collapsible list (the sampler's nav is the prototype) |
| App Layout | shell: title bar + drawer + content slot |
| Custom Field | formalize the composed typed-field pattern — or *reject* it as a shared base (COP: inherit to *be*, not to share); `D_integer_field` already sketches the taxonomy |
| Message Input / Message List / Login | nothing — pure assemblies, good example fodder |
| Upload | reinterpret as a file-chooser dialog (`file_commander` has the ingredients) |
| Icon | a glyph / Nerd-Font constants module |

## Tier 3 — design tension or marginal

- **Scroller** — scrolling *arbitrary* content needs clipping/viewport
  machinery and pushes against the top-down layout invariant (it wants to
  measure content). Best kept as a documented road-not-taken.
- **Tooltip** — competes with Tuile's status-bar `keyboard_hint` idiom.
- **Card** — overlaps `Window` almost entirely.
- **Avatar / Avatar Group** — initials in a box; little value on a TTY.
- **Not applicable:** Field Highlighter (collaboration), Themable Mixin
  (covered by `Theme`).

## Infrastructure that gates clusters

These are prerequisites, not components, and each deserves its own idea
file when its cluster comes up:

1. ~~**Box layouts** (H/V)~~ — **done** 2026-08-07 (`D_box_layouts`). Turned
   out *not* to be structural: a `Box` is an `Absolute` subclass with a `rect=`
   override, so it unblocked the form-shaped cluster without touching the
   foundation. A future Grid should reuse its `Fixed`/`Percent`/`Expand`
   constraints per row and column rather than invent a second vocabulary.
2. **Field label + helper text seam** → Form Layout. Note this is what Form
   Layout is actually blocked on — the layout half now exists. Designed
   2026-09-03 and **half shipped the same day**: the caption goes to the layout
   (fields do *not* include `HasCaption` — `D_caption_ownership`), and the error
   *verdict* stays on the field as `Component::HasValidation` (one member,
   `error_message`, `HasValue` includes it, painted as a red *well* —
   `D_has_validation`). What is left is the container that reads the *message*
   off the field and paints it inline-right, plus the required marker and helper
   text: `ideas/form-layout.md`. Items 2 and 3 turn out to be the same seam cut
   in two — this half is the *geometry*, item 3 is the *signals*.
3. **Validation seam** → forms generally. Designed 2026-09-03 and split three
   ways. The field-side channel **shipped the same day**: `HasBadInput`
   (`D_bad_input`) holds the one fact only the field can know, because
   `on_value_change` is a diff over values and every unrepresentable input
   collapses onto the same one, and `on_blur` — the commit point it wanted —
   shipped 2026-09-04 (`D_on_blur`); only the push notice is still deferred, for
   want of a consumer. Still open: `ideas/binder.md`
   (the consumer, and the four-layer model/transformations/value/input
   vocabulary the whole cluster now uses). The `HasValidation` half **shipped
   the same day** as well (`D_has_validation`), so what is left of item 2's note
   is the container that paints the message. `Date Picker` is the component that
   actually forces it; Email Field is re-tiered toward *reject*.
4. **Anchored Popover extraction** → pickers, Tooltip. **No longer gates Menu
   Bar** — `D_menu_bar` argues the side-anchor is a sibling method on
   `ListDropdown`, since both callers still wrap a `List`; the extraction's
   trigger is now the first non-`List` content that wants anchoring.
5. **Mouse motion/drag** (modes 1002/1006, release events) → Split
   divider, Slider drag, scrollbar drag.
6. **Typed items + data provider on `List`** → List Box, Grid, Virtual
   List. **Half done** 2026-08-14 (`D_list_items`): `List` takes `items` +
   a `renderer` and renders only the visible rows, and the five composers
   are folded onto it. The remaining half is *sourcing* items lazily (a
   data provider behind `items`), which lazy rendering was chosen to keep
   reachable without a redesign.

Vaadin's `Binder` is the natural companion for the forms cluster but is
not a component; `D_has_value` already parks the forms-layer questions
(converters, read-only, required indicator).

## ~~Cross-cutting open question: component color slots vs. theme tokens~~

**Settled 2026-08-01 as `DECISIONS.md` `D_color_slots`** — the slot, defaulting
to `nil`. Slider and Badge are bound by it when they land; Badge's promotion
trigger (a *second* built-in needing the same semantic color) is written up
there, so neither has to re-argue it.
