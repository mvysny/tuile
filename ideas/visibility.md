# `Component#visible=` — implementation brief

**Status:** designed and **decided**, 2026-09-05 — every ruling lives in
`DECISIONS.md` `D_visibility`; read that first, it is the authority and this
note does not restate it. What remains here is the brief for whoever codes
it: the touch list, the specs, the docs to flip, and how to retire this note.
The research behind the decision is `ideas/visibility/toolkit-survey.md`
(24 toolkits, verified against docs and source); it dies with this note, and
`D_visibility` already carries the nuggets it needs from it.

## The one-paragraph spec

`Component#visible?` / `#visible=`, default `true`. `false` = *gone*: **as if
detached, but it stays in the tree** — paints nothing, takes no space in a
`Box` (placement kept, no `spacing` gap), invisible to focus, keys, cursor and
mouse; keeps its parent, rect, state and running resources, and **no lifecycle
hook fires**. Never say or write "hiding is detaching": the analogy is about
what the user can reach, and `on_detached` is the one place it breaks.
Ancestor-inclusive: every walk prunes a hidden subtree at its root. Hiding the
focused subtree refocuses the hidden component's *parent* — reuse
`on_child_removed`'s focus-repair half, not its detach — never `nil`, never
restored on re-show.
`Screen#focused=` raises on a hidden target. `Overlay#visible=` raises.
`Testing.find` / `get` never return a hidden component; the failure message
counts the hidden matches it excluded; `dump` shows and marks them.

## Touch list

Framework core (`lib/tuile/`):

- `component.rb` — `@visible` (default `true`), `visible?`, `visible=`
  (no-op on same value; on flip: focus repair if the focused component is in
  this subtree, `parent&.__send__(:on_child_visibility_changed, self)`,
  `on_tree { screen.invalidate(_1) } if attached?` — the `bg_color=` shape);
  protected `on_child_visibility_changed(child)` default no-op; one shared
  walk helper for shown-only pre-order (`on_shown_tree`, or
  `on_tree(shown_only: true)` — pick one, use it in all four focus walks and
  in `Testing`); `children_tile_rect?` skips hidden children;
  `handle_mouse` skips hidden children; `inspect_details` adds `hidden`
  (via `super + [...]`, the mixin seam).
- `screen.rb` — drain filter in `#repaint` gains the hidden-ancestor term
  beside the empty-rect one; `cycle_focus` uses the shown walk;
  `focused=` raises `Tuile::Error` on a hidden target (message names
  the component, like the detached case).
- `screen_pane.rb` — `first_tab_stop_or_root` uses the shown walk.
- `component/layout.rb` — `Layout#on_focus` uses the shown walk.
- `component/has_content.rb` — `on_focus` forwards only to shown content.
- `component/layout/box.rb` — `main_sizes` / `place_children` iterate shown
  children only; hidden ones get `Rect.new(rect.left, rect.top, 0, 0)`;
  `on_child_visibility_changed` → `relayout`; the `Fixed` rdoc's collapse
  note gains "a hidden child costs no gap".
- `component/overlay.rb` — `visible=` raises (`D_overlay`: close it).
- `testing.rb` — `find` walks shown only; `failure` counts hidden matches
  (walk the *full* tree with the same spec, subtract); `dump` walks the full
  tree, marks excluded matches with a second glyph beside `→`.
- `sig/tuile.rbs` — `rake sig`, commit the result.

Do **not** touch: `on_tree` itself (lifecycle, theme fan-out, `active=`
marking and `bg_color=` invalidation must keep reaching hidden components);
`parent=` / the lifecycle hooks; `TabSheet` (stays on detachment).

## Specs

- `component_spec.rb` — flag default, no-op on same value, ancestor-inclusive
  pruning, focus repair to parent (and the `nil`-never case: after hiding the
  focused field, `q` does *not* reach the loop — assert the scope root sees
  the key), raise on focusing a hidden target, no `on_attached` /
  `on_detached` on flip, `children_tile_rect?` treats a hidden child as a gap
  (its stale cells are blanked), mouse skips hidden children.
- `screen_spec.rb` — drain filter drops hidden and hidden-ancestor
  components; a hidden component invalidated then shown repaints.
- `box_spec.rb` — hidden middle child: siblings close up, **no double gap**
  under `spacing: 1`, hidden rect is empty at the origin, placement survives a
  hide/show round-trip (`Fixed[1], cross: Fixed[30]` intact), `Expand` shares
  re-divide, `constrain` on a hidden child takes effect on show.
- `overlay_spec.rb` / `popup_spec.rb` — `visible=` raises.
- `testing_spec.rb` — `find` skips hidden, skips under a hidden ancestor;
  `get` failure text includes `(1 hidden match excluded)`; `dump` lists the
  hidden component with its marker.
- `component_contract_spec.rb` — a fourth invariant over the catalog: hide →
  paints nothing and is not a Tab stop; show → same rect and cells as before
  (compare `region_text` before hide and after show).
- A sampler pane: a form with a checkbox that hides two fields below it under
  `spacing: 1`, so the gap rule is visible by eye; the PTY spec cycles it.

## Docs to flip in the same commit

- **AGENTS.md** "Hiding a component means *detaching* it" (Component tree
  section) → hiding is `visible = false`: *as if detached, but still in the
  tree*, so no hook fires; the flag is ancestor-inclusive and
  component-side, so a container that never heard of it degrades to a hole,
  not a leak; `TabSheet` detaches *for the lifecycle hooks*; `Fixed[0]` is a
  collapse; `remove` / `add(at:)` is the move when the hooks should fire.
  Delete the re-grow rule (met). Add the two cross-file invariants that clear
  the gate: *every shown-only walk goes through the one helper* (a new focus
  walk that uses bare `on_tree` re-opens the `D_tabs` leaks), and *a new
  container with arithmetic overrides `on_child_visibility_changed`*.
  Also the Testing section: `find` simulates a user and never finds a hidden
  component. Layout list: no new file, so no row.
- **book ch7** "Hiding a component means detaching it" → rewrite around the
  flag; keep the `TabSheet`-detaches paragraph as the lifecycle case. Book
  ch5 (focus): one paragraph on what happens when the focused field is
  hidden.
- **`D_tabs`**, **`D_empty_ancestor`** — already amended; nothing to do.
- **CHANGELOG** — one `Add` sentence naming `Component#visible=`, plus one
  for `Testing.find`'s policy, `See DECISIONS.md D_visibility`.
- **TERMINOLOGY.md** — `hidden` / `shown` if the words are used in rdoc with
  the ancestor-inclusive meaning.
- **README** Components table — no new component, no row.

## Retiring this note

Graduation per AGENTS.md's pipeline: rdoc carries the per-symbol contract,
AGENTS.md the two cross-file invariants above, the book the *why*, and
`D_visibility` already has the decision. Then `git rm ideas/visibility.md
ideas/visibility/toolkit-survey.md` and drop `D_visibility`'s two pointers to
them (its `Status:` line). Check `ideas/form-layout.md` — it should gain one
line saying a `FormLayout` overrides `on_child_visibility_changed`.
