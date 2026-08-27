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
| Confirm Dialog | `Popup`+`Window`+`Button` | fold `PickerWindow` in |
| Details → Accordion | `HasContent` | Details is the atom, Accordion the group |
| ~~Tabs → TabSheet~~ | plain `Component` + the tree API | **built** 2026-08-23 (`D_tabs`, book ch7); a strip (one tab stop, Left/Right, immediate activation) plus a sheet whose `children` are `[strip, pane]`. Neither is `HasValue` — a tab selection is view state — and neither is `HasContent`; hiding a pane means *detaching* it, since Tuile has no visibility flag; the strip owns mutable `Tabs::Tab` handles rather than the `items`/`item_label` shell. Hidden/disabled/closeable tabs, lazy panes and a scrolling strip are deferred, each additive (`D_tabs`) |
| Popover | `ListDropdown#anchor_to` (extracted 2026-08-12) | generalize the anchored non-modal overlay: `anchor_to` moves down to it and `ListDropdown` inherits it. Build it when the second *kind* of anchoring appears (a point; a right edge that flips) — not the second caller of the same kind. Nothing gates on it today: Menu Bar shipped without it |
| ~~Menu Bar~~ | `ListDropdown` (+ `anchor_beside`) | **built** 2026-08-24 (`D_menu_bar`, book ch7), mnemonics the same day. Turned out *not* to need the Popover extraction: a focused strip drives a cascade of non-modal `ListDropdown`s the way `Select` drives one, so the additions were a side-anchor method, a highlighted-row rect and a cursor pass-through. Unlimited submenu depth; checkable/disabled items and global-shortcut activation deferred indefinitely |
| Slider | `draw_line` | arrows/PgUp; 25.2 also has a two-thumb *range* variant |
| Breadcrumbs | `Label`/`StyledString` | clickable path segments |
| Markdown | `TextView` + `StyledString` | Markdown subset → styled text; high value on a TTY |

## Tier 2 — worth doing, each blocked on a new seam

| Component | Blocked on |
|---|---|
| **Grid** (the flagship gap) | column model + renderer strategies + typed items + horizontal scroll (L) |
| Form Layout | a field label/helper seam (Vaadin's `HasLabel`) — Tuile fields carry no caption |
| Email Field | a validation seam (`HasValidation`: invalid state + error line) |
| Date / Time / DateTime Picker | calendar-grid popup over Popover (L) |
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
   Layout is actually blocked on — the layout half now exists.
3. **Validation seam** → Email Field, forms generally.
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
