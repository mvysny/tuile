# Components Vaadin has and Tuile doesn't

**Status:** a roadmap, surveyed against Vaadin 25.2 (54 OSS components). Each component we decide to
build gets its own idea file; retire this one once what's left is built or rejected. Shipped
entries are gone — their `D_` entries are their home.

**Counterparts today:** Button, Text/Password/Integer/Number Field (`FloatField`,
`BigDecimalField`), Text Area, Checkbox, Checkbox Group, Radio Group, Select, Combo Box, Date/Time/
DateTime Field, Progress Bar, Notification, Dialog / Confirm Dialog (`Popup`, `Window`,
`ConfirmWindow`), Tabs / TabSheet, Menu Bar, Form Layout + Form Item, Horizontal/Vertical Layout.
**List Box** is half-there: `List` has typed items (`D_list_items`) but no multi-select;
`CheckboxGroup` is the nearest. Tuile-only: `ListDropdown`, `TextView`, `LogWindow`, `Scroller`,
`VerticalScrollBar`.

## Tier 1 — buildable on what exists

| Component | Builds on | Note |
|---|---|---|
| Details → Accordion | `HasContent` | Details is the atom, Accordion the group |
| Slider | `draw_line`, `capture_mouse: :drag` | arrows / PgUp; 25.2 also has a two-thumb range variant; a color is a slot per `D_color_slots` |
| Breadcrumbs | `Label` / `StyledString` | clickable path segments |
| Markdown | `TextView` + `StyledString` | a Markdown subset → styled text; high value on a TTY |
| Split Layout → Master Detail | `handle_mouse_drag` (`D_mouse_dispatch`) | the divider is child chrome that asks through a listener (`D_draggable_scrollbar`) |
| Message Input / List, Login | — | pure assemblies; example fodder |

## Tier 2 — each blocked on a new seam

| Component | Blocked on |
|---|---|
| **Grid** (the flagship gap) | column model, renderer strategies, horizontal scroll (L). Reuse `Box`'s `Fixed`/`Percent`/`Expand` per column, no second vocabulary |
| Virtual List | a lazy data provider behind `List#items`; lazy *rendering* already ships and was chosen to keep this reachable |
| Multi Select Combo Box | `CheckboxGroup` + `ComboBox` |
| `DateField` calendar grid | an anchored overlay for non-`List` content (see *Popover*). Phase 2 of a shipped field — additive, a second way to set `value`; month names are `Locale#month_names`. PageUp/PageDown stepping a month comes with it (`D_date_field`) |
| Side Nav | a hierarchical collapsible list |
| App Layout | a shell: title bar + drawer + content `Slot` |
| Upload | reinterpreted as a file-chooser dialog; `examples/file_commander.rb` has the ingredients |
| Icon | a glyph / Nerd-Font constants module; ambiguous-width rules apply (`D_ambiguous_width`) |
| Custom Field | `design/ideas/composite-field.md` — or reject as a shared base (inherit to *be*, not to share) |

**Popover** isn't a component so much as the seam: move `ListDropdown#anchor_to` / `anchor_beside`
onto a generic anchored `Overlay`. `Overlay::Placement#anchor` already resolves any component, so
the extraction is cheap; the trigger is the first **non-`List` content** wanting anchoring (the
calendar grid, Tooltip), not a second caller of the same kind (`D_overlay`, `D_menu_bar`).

## Tier 3 — tension or marginal

- **Tooltip** — competes with the app's own status line driven from `Screen#on_focus_changed`
  (`D_status_bar`); a framework hint channel may return only as a pulled query.
- **Card** — overlaps `Window` almost entirely.
- **Avatar / Avatar Group** — initials in a box; little value on a TTY.
- **Email Field** — leaning reject: its value *is* its input, so no bad-input state
  (`D_bad_input`); it would contribute only a packaged regex.
- **Not applicable:** Field Highlighter (collaboration), Themable Mixin (`Theme` covers it).

## Deferred on shipped components

Recorded in their `D_` entries, listed here so the roadmap is complete: Checkbox tri-state (settled,
not built — `D_boolean_fields`); Menu Bar checkable/disabled items and global shortcuts
(`D_menu_bar`); hidden/disabled/closeable tabs, lazy panes, scrolling strip (`D_tabs`); segment-aware
Up/Down in `DateField`/`TimeField` (`D_time_field`); form helper text and a required-marker legend
(`design/ideas/form-layout.md`).

## Related

`design/ideas/binder.md` (the forms-layer companion; `D_has_value` parks converters, read-only,
required), `design/ideas/form-layout.md`, `design/ideas/composite-field.md`, `design/ideas/hover.md`,
`D_color_slots` (Slider and a Badge bind to it; Badge's promotion trigger is written there).
