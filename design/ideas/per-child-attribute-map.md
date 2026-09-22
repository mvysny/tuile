# Per-child attribute map — share the shape, or keep hand-rolling?

**Status:** open again. The threshold this note set ("revisit at three") is passed: four containers
hand-roll the same map.

## The hand-rolls

| container | map | default on read |
|---|---|---|
| `Layout::Box` | `@placements`: `child => {main:, cross:, align:}` | `DEFAULT_PLACEMENT` |
| `FormLayout` | `@placements`: `item => {rows:}` | `DEFAULT_PLACEMENT` |
| `Layout::Absolute` | `@rects`: `child => Rect` | none — `fetch` |
| `ScreenPane` | `@placements`: `popup => placement` (+ `@placed_anchors`) | none — `fetch` |

Each is `{}.compare_by_identity` with the same four moves: put on `add`, write on `constrain` /
`placement=`, delete on `remove`, `invalidate_layout`. `TabSheet#@panes` is keyed by a `Tabs::Tab`
handle, not a child, so it is not a fifth. A `Grid`'s per-column specs (`new-components.md`) would
be column-keyed, not child-keyed.

## Question

`Q_map_shape`: a private helper, a protected trio on `Layout` / `Component`, or nothing?

- **Not a public mixin** — nothing outside the container reads the map, so it fails the locator test
  and is pure DRY.
- **Not a `Container` base class** — inherit to *be* a component, never to share code (COP).
- **Never a second copy of ordering** — `children` stays the sole authority (AGENTS.md, `D_tree_api`).
- **Never a measurement channel** — nothing here may ask a child how big it wants to be (`D_declared_size`).
- `ScreenPane` is not a `Layout`, so a home on `Layout` covers three of four.
- Each map is ~6 lines; `D_float_field`'s *duplicate a shallow shell* may still win at four.

## Settled, don't reopen

- **No `HasChildren`** (a many-children `HasContent`): `FormItem` wraps each field
  (`D_form_layout`), so "app's child or my chrome?" is `FormItem`'s question, answered by
  `HasContent` (`D_has_content`). Layouts were the only implementer: `TabSheet` exposes `Tab`
  handles (`D_tabs`), the groups and `Select` hold items (`D_list_items`), `MenuBar` items aren't
  components, popups are machinery.
- **No leak bug:** the tree API is protected, so an app reaches children only through a container's
  own `add` / `remove`; a missing entry reads the default, or raises for the two with none.

## Related

`D_relayout` (why every container keeps where each child wants to be), `D_box_layouts`,
`D_form_layout`, `D_has_content`, `D_tree_api`, `D_declared_size`, `D_float_field`, `D_tabs`.
