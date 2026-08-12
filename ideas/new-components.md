# Components Vaadin has and Tuile doesn't — the survey

**Status:** survey done 2026-07-25 against Vaadin **25.2** (54 free/OSS
components, via the Vaadin docs MCP). This file is the roadmap; each
component we actually decide to build gets its own `ideas/<name>.md`.
Retire this file once the interesting part of the list is either built or
explicitly rejected — the tiering below is the only nugget worth keeping,
and it belongs here, not in a durable doc, because it goes stale as we
build.

Batch 1 ("field components only") is **done** — every idea filed under it has
graduated: `checkbox` (`DECISIONS.md` `D-boolean-fields`) and `checkbox-group`
(`D-checkbox-group`), both built 2026-07-30; `radio-group` (`D-radio-group`),
built 2026-07-31; `progress-bar` (`D-color-slots`, book ch7 "Reporting
progress") and `password-field` (`D-integer-field`'s taxonomy, book ch7
"Editing text"), both built 2026-08-02.

The **box layouts** that headed the gating list below are done too
(`D-box-layouts`, 2026-08-07) — `Layout::Vertical` / `::Horizontal`, plus the
sampler ported onto them.

## What Tuile already has

Seven of the 54 have a counterpart: Button, Text Field, Text Area,
Integer Field, Combo Box (1:1), Dialog ({Tuile::Component::Popup} plus
`Window`/`InfoWindow`/`PickerWindow`), Themable Mixin
({Tuile::Theme}/{Tuile::ThemeDef}). **List Box** is half-there:
{Tuile::Component::List} is line-based, with no typed items and no
multi-select.

Tuile also has pieces Vaadin doesn't name as components — `ListDropdown`,
`TextView`, `LogWindow`, `VerticalScrollBar` — so the gap is not
symmetric.

That leaves ~46 gaps.

## Tier 1 — reachable from what exists (S–M each)

| Component | Builds on | Note |
|---|---|---|
| ~~Box layouts (H/V)~~ | `Layout` | **built** 2026-08-07 (`D-box-layouts`, book ch3); `Vertical`/`Horizontal` over `Box`, additive sugar on top of `Absolute` — no foundation change |
| ~~Checkbox~~ | `HasValue` | **built** 2026-07-30 (`D-boolean-fields`); tri-state still deferred |
| ~~Radio Group~~ | `List` + `HasValue` | **built** 2026-07-31 (`D-radio-group`); composes a `List`, cursor roams and Space selects |
| ~~Checkbox Group~~ | `List` + `HasValue` | **built** 2026-07-30 (`D-checkbox-group`); composes a `List`, frozen `Set` value |
| ~~Select~~ | `ListDropdown` + `HasValue` | **built** 2026-08-12 (`D-select`, book ch7); a *second driver* of `ListDropdown`, not "ComboBox − filter" — it paints its own one-row face and needs no read-only axis. Claims no printable but Space |
| ~~Password Field~~ | `TextField` | **built** 2026-08-02 (`D-integer-field`'s taxonomy — subclass, since a password's value *is* its text; mask default in `D-ambiguous-width`); a `display_text` seam, one mask glyph per character |
| ~~Number Field~~ | `IntegerField` twin | **built** 2026-08-07 as `FloatField` (`D-float-field`) and `BigDecimalField` (`D-bigdecimal-field`, on Tuile's first optional dep); each named for its Ruby value type, deliberate copies of `IntegerField` |
| ~~Progress Bar~~ | `draw_line` + `EventQueue#tick_fps` | **built** 2026-08-02 (`D-progress-bar`, book ch7); a `value` that stays out of `HasValue`, ticker synced from `attached? && indeterminate?` |
| Notification | `Popup` + `Ticker` | needs corner-anchored (non-centered) popup placement |
| Confirm Dialog | `Popup`+`Window`+`Button` | fold `PickerWindow` in |
| Details → Accordion | `HasContent` | Details is the atom, Accordion the group |
| Tabs → Tabsheet | `HasValue` (index) + `HasContent` | strip, then strip + content swap |
| Popover | `ListDropdown#anchor_to` (extracted 2026-08-12) | generalize the anchored non-modal overlay: `anchor_to` moves down to it and `ListDropdown` inherits it. Build it when the second *kind* of anchoring appears (a point; a right edge that flips) — not the second caller of the same kind. Gates the next two |
| Menu Bar | `ListDropdown::Menu` + Popover | |
| Context Menu | same | `:right` button already parses |
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
| Custom Field | formalize the composed typed-field pattern — or *reject* it as a shared base (COP: inherit to *be*, not to share); `D-integer-field` already sketches the taxonomy |
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

1. ~~**Box layouts** (H/V)~~ — **done** 2026-08-07 (`D-box-layouts`). Turned
   out *not* to be structural: a `Box` is an `Absolute` subclass with a `rect=`
   override, so it unblocked the form-shaped cluster without touching the
   foundation. A future Grid should reuse its `Fixed`/`Percent`/`Expand`
   constraints per row and column rather than invent a second vocabulary.
2. **Field label + helper text seam** → Form Layout. Note this is what Form
   Layout is actually blocked on — the layout half now exists.
3. **Validation seam** → Email Field, forms generally.
4. **Anchored Popover extraction** → Menu Bar, Context Menu, pickers,
   Tooltip.
5. **Mouse motion/drag** (modes 1002/1006, release events) → Split
   divider, Slider drag, scrollbar drag.
6. **Typed items + data provider on `List`** → List Box, Grid, Virtual
   List.

Vaadin's `Binder` is the natural companion for the forms cluster but is
not a component; `D-has-value` already parks the forms-layer questions
(converters, read-only, required indicator).

## ~~Cross-cutting open question: component color slots vs. theme tokens~~

**Settled 2026-08-01 as `DECISIONS.md` `D-color-slots`** — the slot, defaulting
to `nil`. Slider and Badge are bound by it when they land; Badge's promotion
trigger (a *second* built-in needing the same semantic color) is written up
there, so neither has to re-argue it.
