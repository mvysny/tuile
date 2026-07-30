# Components Vaadin has and Tuile doesn't — the survey

**Status:** survey done 2026-07-25 against Vaadin **25.2** (54 free/OSS
components, via the Vaadin docs MCP). This file is the roadmap; each
component we actually decide to build gets its own `ideas/<name>.md`.
Retire this file once the interesting part of the list is either built or
explicitly rejected — the tiering below is the only nugget worth keeping,
and it belongs here, not in a durable doc, because it goes stale as we
build.

Filed as separate idea files so far (batch 1, "field components only"):
`radio-group`, `checkbox-group`, `password-field`, `progress-bar`.
`checkbox` graduated (built 2026-07-30; `DECISIONS.md` `D-boolean-fields`).

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
| Box layouts (H/V) | `Layout` | Tuile has only `Layout::Absolute`. Biggest structural win; unblocks half of this table |
| ~~Checkbox~~ | `HasValue` | **built** 2026-07-30 (`D-boolean-fields`); tri-state still deferred |
| Radio Group | `List` + `HasValue` | typed single-select, `(•)` |
| Checkbox Group | Checkbox / `List` | `Set`-valued multi-select |
| Select | `ComboBox` − filter | ComboBox with a read-only field; near-free. Deferred once already in `D-combobox` (wants the parked read-only axis) |
| Password Field | `TextField` | masked repaint only |
| Number Field | `IntegerField` twin | same composed-field shape, `Float` |
| Progress Bar | `draw_line` + `EventQueue#tick_fps` | ticker for the indeterminate mode |
| Notification | `Popup` + `Ticker` | needs corner-anchored (non-centered) popup placement |
| Confirm Dialog | `Popup`+`Window`+`Button` | fold `PickerWindow` in |
| Details → Accordion | `HasContent` | Details is the atom, Accordion the group |
| Tabs → Tabsheet | `HasValue` (index) + `HasContent` | strip, then strip + content swap |
| Popover | extract `ComboBox#anchor` + `ListDropdown` geometry | generalize the anchored non-modal overlay; gates the next two |
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

1. **Box layouts** (H/V) — everything form-shaped wants them.
2. **Field label + helper text seam** → Form Layout.
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

## Cross-cutting open question: component color slots vs. theme tokens

Raised by `progress-bar` (where it's written up in full) and due again at
Slider and Badge: when a component needs a color the four
{Tuile::Theme} chrome tokens don't cover, does it get a
`Color | Theme::Ref` **slot** on the component (`bar_color=`, resolved at
paint like `bg_color`), or does {Tuile::Theme} grow a **token**? The slot
keeps the theme's public `Data` member list stable and suits app-branded
colors; a token suits genuinely semantic ones (Badge's
info/success/warning/error). Settle it once, then apply it to all three —
and don't let any single component add a token on its own.
