# `Component#visible=`: a *gone* flag, kept in the tree

**Status:** brainstorm, 2026-09-05. Grew out of issue #17's redesign section and
the discussion under `D_empty_ancestor`, which deferred exactly this under
`D_tabs`' re-grow rule. Graduates into a `D_visibility` entry (the choice and
the roads not taken), `Component#visible=` rdoc (the per-gate contract), a
rewrite of the "Hiding a component means detaching it" paragraphs in AGENTS.md
and book ch7, a `Box` rdoc amendment, a contract-suite invariant, and a
CHANGELOG line. Note retired then.

## The case, restated honestly

`D_tabs` chose detachment for `TabSheet` and recorded *why the empty rect is
not hiding* (five silent leaks: Tab cycle, both focus cascades, the cursor,
key bubbling). Read carefully, that entry is an argument **against zero-rect
hiding**, and for detachment *as `TabSheet`'s implementation*. It is not an
argument against a visibility flag — its own re-grow rule says the flag comes
back when a second consumer appears, argued as a focus-and-paint gate with a
ruling on layout arithmetic. This note is that argument.

**The second consumer is the conditional form field.** A form hides fields
based on choices above them ("Company name" only when "Business customer" is
ticked). Today's sanctioned answer, after #17, is `box.remove(field)` and
`box.add(field, Fixed[1], at: i)`. Three things make that the wrong tool for a
form:

- **The app has to know `i`**, and `i` moves: an insert above the hidden field
  shifts it, and two fields hidden and re-shown in a different order than they
  were hidden land in each other's places. The form implementor ends up
  keeping a shadow copy of the child order — the second-copy-of-ordering
  `D_tree_api` forbids the *framework* from keeping, pushed onto every app.
- **The constraints go with the child.** `remove` drops `@placements[child]`,
  so the show path has to re-state `Fixed[1], cross: Fixed[30]` from
  somewhere — a third thing to keep beside the field and its index.
- **Detach fires lifecycle.** For a field that is fine; for a pane holding a
  running job or a subscription (`D_empty_ancestor`'s "must stay mounted and
  live" case, which pikuri-tui's sidebar may be) it tears down the resource
  the app wanted kept. Vaadin's `setVisible(false)` keeps the component
  attached and its listeners registered for the same reason.

And the two geometric workarounds both fail the form, in ways #17 already
measured: `Fixed[0]` (`constrain`) still costs its `spacing` gap — a
`spacing: 1` form shows a two-row hole where the field was — and it still keeps
the field's tab stop, so Tab lands on a field the user cannot see and the next
keystroke types into it. A `Slot` around each conditional field with
`slot.content = nil` keeps the position and detaches cleanly, but an empty
`Slot` does not collapse (`D_slots`): one row of hole *plus* the gap.

So the requirement is Android's `GONE`, and only `GONE`: **the component stays
attached, paints nothing, takes no layout space in a `Box`, and is invisible to
focus, keys, the cursor and the mouse.** Not `INVISIBLE` (keep the slot,
paint nothing) — a `Slot` with `content = nil` already *is* that, which is a
nice accident: Tuile gets both Android states without an enum.

## Proposal

```ruby
field.visible = false      # gone
field.visible = true       # back, in the same place, with the same constraints
field.visible?             # the component's own flag
```

Boolean, on `Component`, default `true`. One flag, no enum, no `display`
string.

### What "gone" means, gate by gate

The flag is an **ancestor-inclusive** condition: a component is *shown* iff it
and every ancestor are `visible?`. Every walk below prunes the whole hidden
subtree at its root rather than testing each leaf, so a `TextField` three
levels under a hidden panel is skipped without knowing it.

| gate | today | with the flag |
|---|---|---|
| paint | `Component#repaint` returns on own empty rect; `Screen#repaint`'s drain filter drops empty-rect ancestors (`D_empty_ancestor`) | the drain filter also drops a hidden component or one under a hidden ancestor — the same AND, one more term, at the one choke point |
| parent's gap clear | `children_tile_rect?` sums children's rects | excludes hidden children, so a hidden child's cells count as a gap and the parent blanks them — this is what actually erases the field from the screen in an `Absolute`, where nobody re-assigns its rect |
| Tab cycle | `Screen#cycle_focus` collects `tab_stop?` over `on_tree` | prunes hidden subtrees |
| focus cascades | `ScreenPane#first_tab_stop_or_root`, `Layout#on_focus`, `HasContent#on_focus` | same pruning; a `HasContent` whose content is hidden forwards nowhere |
| focus assignment | `Screen#focused=` raises when the target is detached | also raises when the target is hidden: focusing what the user cannot see is the cursor-in-the-visible-pane bug, and it should fail loudly at the call site |
| hiding the focused subtree | n/a | focus repair, the same path a detach takes (`on_child_removed`'s walk-up-and-refocus-parent, which then cascades to the first *shown* tab stop) |
| cursor | `Screen#cursor_position` asks `focused` | follows from the two rows above: the focused component is always shown |
| keys | bubble from `focused` up | follows: a hidden component is never on the focus chain |
| mouse | `Component#handle_mouse` routes to children whose rect contains the point | skips hidden children (belt to the empty-rect braces; an `Absolute` child keeps its rect) |
| lifecycle | `on_attached` / `on_detached` from `parent=` | **unchanged — nothing fires.** That is the feature. |
| `invalidate` | no-op when detached | still records; the drain filter discards. Showing again re-invalidates the subtree (`on_tree`), like `bg_color=` |
| `Testing.find` / `get` / `dump` | tree walk | finds hidden components too (a test asserts a field *is* hidden); `inspect_details` says `hidden` |

### Layout arithmetic — the ruling `D_tabs` demanded

- **`Box` skips a hidden child entirely**: it is out of the `count` that
  prices `spacing * (count - 1)`, gets no share of `available`, and is assigned
  the empty rect at the box's origin (the same rect the `inner.empty?` branch
  assigns). Its placement entry is **kept**, so `visible = true` puts it back
  with `Fixed[1], cross: Fixed[30]` intact. This is the one place "gone"
  reclaims space, and it is what makes a `spacing: 1` form close up cleanly.
  It amends `D_empty_ancestor`'s last road-not-taken: `Fixed[0]` keeps costing
  its gap (a collapsed child is still a member of the sequence), a hidden child
  costs nothing (it is not).
- **`Absolute` does nothing.** Its `rect=` is app arithmetic; the app that
  wants the space reclaimed reads `child.visible?` in its own pass. A hidden
  child that keeps its rect is harmless because every other gate is
  component-side — it paints nothing, its cells are blanked by the parent's gap
  clear, it takes no focus and no clicks. That is the design's load-bearing
  choice: **the gates live on the component tree, not in the containers**, so
  a forgetful container degrades to a hole rather than to a leak.
- **`Window` / `Popup` / `Slot` / `HasContent`**: single-child, nothing to
  reclaim. A hidden content leaves the inner area blank, the way an empty
  `Slot` does today. `Window` keeps its border.
- **`Box` needs to hear about the flip.** A `visible=` on a child must
  relayout the parent, and `Box` is the only container with arithmetic, so:
  one protected upward hook `on_child_visibility_changed(child)`, default
  no-op, `Box` overrides with `relayout`, a future `FormLayout` likewise. Same
  shape as `on_child_removed`. (Alternative: `visible=` invalidates the parent
  and `Box` re-derives — no, `Box` must re-*place*, not just repaint.)

### Overlays

`Overlay` / `Popup` / `Notification` have their own lifecycle (`close`,
`Screen#remove_popup`) and the pane consults `@popups` for hit-testing and
`modal_popup` for key scope. A hidden popup would still be modal and still
catch clicks. Two honest options: `visible=` **raises** on an `Overlay`
("close it instead", `D_overlay`), or `ScreenPane` learns to skip hidden
popups in `modal_popup` / `handle_mouse`. Recommend **raise**: the
"hidden-but-live" motivation does not apply to an overlay (it is dismissed,
not hidden), and teaching the pane a second axis of overlay liveness is where
the `focusable?`-and-`modal?`-move-together trap came from.

### `TabSheet` stays on detachment

Nothing forces it over. Detachment gives it lifecycle hooks on switch (the
`ProgressBar` ticker stops), which is a feature the book teaches. A future
`keep_alive` / lazy-pane option could use the flag; not this note's business.

## Prior art — verified, 24 toolkits

Full per-toolkit notes with source URLs: `ideas/visibility/toolkit-survey.md`.
The four findings that decide the design:

1. **A single boolean meaning *gone* is the mainstream default.** Qt, GTK4,
   Vaadin, Lanterna, WinForms, AppKit stack views, Flutter's `Visibility`,
   Textual's `display`, FTXUI's `Maybe`, Tk's `grid remove` all hide as gone.
   Where a keep-the-space variant exists it is the *opt-in* — Qt
   `setRetainSizeWhenHidden`, Flutter `maintainSize`, Swing
   `GroupLayout.setHonorsVisibility(false)`, AppKit
   `detachesHiddenViews = false`. Only JavaFX `visible`, SwiftUI `.hidden()`
   and CSS `visibility` default to keep-space, and each pairs it with a
   separate gone mechanism (`managed`, `if`, `display`). So: one boolean,
   gone, and `Slot`-with-no-content as the keep-space idiom is exactly the
   industry shape.
2. **Box layouts price spacing over shown children only.** Qt `QBoxLayout`
   (`previousNonEmptyIndex`), GTK `GtkBoxLayout`
   (`(n_visible_children - 1) * spacing`), Lanterna `LinearLayout`
   (`spacing * (visible.size() - 1)`), AWT `FlowLayout`, Android
   `LinearLayout` (its dividers too), AppKit stack views. The one double-gap
   trap is Swing `BoxLayout`, and only because its gaps are strut
   *components* that don't hide with their neighbour — Tuile's `spacing` is a
   number, so the trap doesn't apply. `Box` skipping the gap is therefore
   the expected behaviour, not a Tuile-specific ruling.
3. **Every toolkit with a documented focus model gates it on visibility,
   none on geometry.** Textual (`focusable` requires `visible`; the focus
   chain walks `displayed_children`), blessed, Lanterna ("invisible
   components cannot get input focus"), Turbo Vision (`findNext` masks on
   `sfVisible`), Android, Swing's traversal policy, JavaFX, WPF, WinForms
   (`CanSelect` walks *all* parents), Tk, AppKit, Vaadin (server drops
   events). Several also **repair focus on hide**: blessed `rewindFocus`,
   AppKit hands off to `nextValidKeyView`, Turbo Vision `resetCurrent`,
   JavaFX "never maintain keyboard focus when they become invisible". The two
   documented exceptions are deliberate (Flutter `Offstage`) or a known gap
   (Ink). This is `D_empty_ancestor`'s measurement from the other side, and
   it settles that the flag must be ancestor-inclusive and must repair focus.
4. **Switchers split evenly between the flag and detachment.** Flag: Textual
   `ContentSwitcher`, Swing `CardLayout` / `JTabbedPane`, Android
   `ViewAnimator`, Qt `QStackedLayout`, GTK `GtkStack`. Detachment: urwid,
   Flutter's default `Visibility`, SwiftUI / Compose conditionals, AppKit
   `detachesHiddenViews`. So `TabSheet` staying on detachment is
   unremarkable, and there is no pressure to move it.

Two details worth stealing: Vaadin's "children inherit" (the flag is read
along the ancestor chain, exactly the pruning above) and GTK's split between
`visible` (the widget's own, public) and `child-visible` (a container-only
override `GtkStack` uses) — the second is what a future keep-alive `TabSheet`
would want, and it is deliberately *not* in this note.

## Cost, so it is not undersold

One flag, one upward hook, and gates in: the drain filter, `children_tile_rect?`,
`cycle_focus`, `first_tab_stop_or_root`, `Layout#on_focus`,
`HasContent#on_focus`, `Screen#focused=`, `Component#handle_mouse`, a focus
repair in `visible=`, `Box#main_sizes` / `place_children`, an `Overlay`
refusal, and `inspect_details`. Plus a walk helper (`each_shown` or
`on_tree(shown_only: true)`) so the four focus walks share one pruning rule
rather than four copies. The contract suite gets a fourth invariant: *a
hidden component paints nothing, is not in the Tab cycle, and reappears where
it was*, run over the catalog.

Docs to flip: AGENTS.md "Hiding a component means detaching it" (becomes
"hiding is `visible = false`; `TabSheet` detaches for the lifecycle hooks"),
book ch7 §"Hiding a component means detaching it", `Fixed`'s collapse note,
`D_tabs`' re-grow rule (satisfied), `D_empty_ancestor`'s "hiding is still
detachment" decision (amended).

## Roads not taken (draft, for `D_visibility`)

- **A `Hidden` / `Gone` `Box` constraint** (`constrain(field, Gone)`). Parent-side
  only, so it reclaims space but leaves every focus leak `D_tabs` listed —
  it is `Fixed[0]` with better branding, the exact thing `D_empty_ancestor`
  refused.
- **An enum (`:visible` / `:invisible` / `:gone`)**. The middle state is a
  `Slot` with no content, and a hidden-but-space-keeping field has no form
  use; an enum invites `:disabled` next.
- **`visible=` detaching under the hood** (sugar over `remove` / `add(at:)`).
  Fires lifecycle, loses the "live while hidden" case, and only `Box` could
  implement it (an `Absolute` has no `at:`).
- **A `shown?` public reader** for the effective state. Not needed: the walks
  prune at the hidden root, and a reader that walks ancestors is one more
  thing to keep un-cached. Add only if an app needs it.

## Open

- Name: `visible` / `visible=` / `visible?` (Vaadin, Swing, `D_tabs`' own
  wording) vs `hidden` / `hidden=` (HTML attribute, AppKit `isHidden`).
  `visible` — the re-grow rule already names it, and `scrollbar_visibility`
  is the sibling vocabulary.
- Does `visible = false` on the component holding focus repair to the *next*
  tab stop (a form's natural flow) or to the parent's cascade (first stop in
  the scope, which is what `on_child_removed` does today)? Reusing the detach
  path is consistent; the form may prefer "next". Decide with a sampler pane.
- Should `Testing.find` grow a `visible:` filter, or is asserting
  `refute field.visible?` enough?

## Related

`D_tabs` (the re-grow rule this satisfies), `D_empty_ancestor` (collapse is
not hiding; `add(at:)` / `constrain`), `D_slots` (an empty slot does not
collapse — the `INVISIBLE` state), `D_box_layouts` (a gap belongs to the
sequence), `D_overlay` (dismiss, don't hide), `D_attach_hooks` (what a
hidden-but-attached component keeps running), `D_component_contract` (the
suite that gets the fourth invariant), `ideas/form-layout.md` (the consumer
that needs this most, once built).
