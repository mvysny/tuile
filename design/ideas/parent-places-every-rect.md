# Should every rect come from the parent's `relayout`, popups included?

**Status:** brainstorm, 2026-09-22. Nothing built. Grew out of proof-reading the unmerged
`strict-layout-diagnostic` branch, whose `ScreenPane#places_child?` this file proposes to
overturn. The open questions at the bottom are the point.

## The proposal

**Every container keeps a per-child constraint saying where that child wants to be, and its
`relayout` is the only code that turns it into a rect. Nothing else moves anything:
`Component#rect=` becomes protected.**

| container | per-child constraint | changed by |
|---|---|---|
| `Vertical` / `Horizontal` | `Fixed` / `Percent` / `Expand` (exists) | `add`, `constrain` |
| `Absolute` | a `Rect` | `add(child, rect)`, `constrain(child, rect)` |
| `ScreenPane`, content | fills the pane (exists) | `content=` |
| `ScreenPane`, a popup | a placement: `At[rect]`, `Centered[size]`, `Anchored[…]`, `TopRight[…]` | `open`, then a change of placement |

Moving a child means changing its constraint. That is an input to the parent's `relayout`, so the
parent marks, the settle places the child, and the flow is the one a `Vertical` already runs. No
exceptions.

## Why: the rule is already almost true

`D_relayout` made `relayout` "the sole writer of a child's rect". In `lib/`, every `rect =` already
sits in a parent's `relayout` (`Box`, `Window`, `Slot`, `TabSheet`, `FormItem`, the scrollbars, the
wrapping fields) except these:

- **The overlays set their own rect:** `Popup#reposition` and `#center`, `ListDropdown#anchor_to` /
  `#anchor_beside`, `Notification#reposition`, and the caller of a bare `Overlay`.
- **`ScreenPane#rect=` is a second layout pass for popups only**, calling `@popups.each(&:reposition)`
  on a resize.
- **`Screen` assigns the pane's rect.** This one is legitimate: the screen stands in for the pane's
  parent.

The `strict-layout-diagnostic` branch hit a consequence of the first two. Opening a popup marks the
pane (`add_child` marks every time), the pane's `relayout` can't use the mark, and the diagnostic's
ancestor walk then reported every rect under `content` as stale. The branch's fix was
`places_child?`, a per-container declaration that skips the mark. That is a third special case
covering for the first two. With this proposal, the mark is honest: the pane *does* place its
popups in `relayout`.

## What this overturns

`D_relayout`'s *Why not* rejects "a `ScreenPane#relayout` that also repositions the popups"
because it "snapped a hand-placed popup back to centre whenever a second one opened". That is only
true while the popup's **rect is the only record of where it wants to be**. With a stored
placement, a hand-placed popup's constraint *is* `At[its rect]`, so a re-run gives the same rect,
`rect=` returns early, and nothing moves. Every `reposition` in `lib/` is already a pure function of
the screen size plus the overlay's own state. `declared_size` is already an intent the popup is
"re-read from on every layout pass" (`D_declared_size`); this finishes the job.

## What we gain

- **One layout path.** The `ScreenPane#rect=` override goes (a resize marks the pane like any rect
  change), `places_child?` never lands, and a bare `Absolute` gets a real `relayout`. The last also
  retires the branch's `relayout_assigns_rects?`, the diagnostic's other special case.
- **An open dropdown follows its field** through a resize or a relayout of the content around it,
  where today's snapshot leaves it behind.
- **A bare overlay survives a terminal shrink.** `At[rect]` can clamp to the screen; a caller-set
  rect today keeps its top-left even when that is off-screen.
- **A precise diagnostic becomes possible.** See `design/ideas/stale-rect-diagnostic.md`.

## What we lose

- **Assigning a rect and reading it straight back.** `w.rect = …; w.rect` stops working; you change
  the constraint and settle. `D_deferred_layout` already says that is the only reliable way, so this
  loses a shortcut, not a capability.
- **Churn.** About 540 `.rect =` assignments across `spec/`, `examples/` and `book/`. Most are spec
  fixtures and should become `mount_at(c, rect)`, which is already "hold it in an `Absolute` at
  this rect" in all but name.
- **The bare `Overlay`'s `o.rect = …; o.open`** becomes a placement. It's a breaking change, which is
  fine before 1.0.

## Open questions

### `Q_placement_home` — does a popup's placement live on the pane or on the overlay?

**Settled (2026-09-22): on the pane, set once at `open`, with the numbers read live from the popup.**
That's the same shape as `Box`, where a child's `Fixed[1]` never changes when its content does: the
constraint is the rule, not the numbers. `Centered[:declared]` reads `popup.declared_size` during
the pass, `TopRight[:measured]` asks the notification for its size, and `Anchored[…]` asks the
dropdown for its row count. After `open`, a popup whose size changes only calls
`parent.invalidate_layout`; it never re-constrains itself. Each overlay class supplies a default
placement (`Popup` centered, `Notification` top-right, `ListDropdown` anchored), and
`open(placement)` overrides it. The reasoning that got there:

`Box` keeps constraints in its own per-child map; a child has no idea it is `Fixed[1]`, because the
constraint is the *container's* vocabulary and the child could sit in any container. The same shape
for popups means `ScreenPane` keeps `{popup => placement}`, filled by `open(placement)`.

Two things argue for keeping it on the overlay instead, as `declared_size` is today:

- **An overlay has exactly one possible parent** (the branch's `check_parent` enforces that), so the
  "could sit in any container" argument is empty and the placement vocabulary is fixed.
- **Most placement changes come from the overlay's own logic.** `Notification` grows as messages
  arrive, `ComboBox` shrinks its dropdown as the filter narrows, `ConfirmWindow` re-measures. On the
  pane's map, each of those reaches into its parent to re-constrain itself.

A middle road: the placement lives on the pane, and the overlay supplies a *default* one (`Popup`
centered, `Notification` top-right, `ListDropdown` anchored). A placement can also hold a
*measured* size that it asks the overlay for during the pane's pass (`Centered[:measured]`), so a
measurement change only needs `parent.invalidate_layout` and never a new constraint. That is the
same "read-only, caller-side query" `D_declared_size` allows, with the pane as the caller.

### `Q_absolute_role` — is `Absolute` the `Rect` holder or the arithmetic base?

**Settled (2026-09-22): `Absolute` holds a `Rect` per child, and custom arithmetic subclasses
`Layout`.** The class then does what its name says, and becomes `mount_at`'s holder. The book's
`SplitPane`, `sampler.rb`'s `Panel` and `file_commander.rb`'s `FileCommander` move to `< Layout`.
The reasoning that got there:

Today `Absolute` is the class you subclass to write your own `relayout` (`book/03-layout.md`'s
`SplitPane`, `sampler.rb`'s `Panel`, `file_commander.rb`'s `FileCommander`). A *bare* `Absolute`
with caller-set rects appears only as a spec fixture (`mount_at`, about 27 spec files). Giving it
`Rect` constraints mixes the two meanings: a subclass that overrides `relayout` silently ignores the
constraints it was given. `class Absolute < Layout; end` is empty today, though: it is a name for
"the `Layout` you subclass", so moving the arithmetic role onto `Layout` itself costs three renames
outside `spec/`. Options:

- `Absolute` holds `Rect` constraints; custom arithmetic subclasses `Layout` directly, and the book
  changes to match.
- `Absolute` stays the arithmetic base, and the `Rect` holder is a spec-support fixture (or a new,
  plainly named layout).

### `Q_anchor_order` — how does an anchored popup read a rect the same settle is still moving?

**Settled (2026-09-22): option 1 below.** The anchor is an input to the pane's `relayout`, so a
moved anchor marks the pane. It is detected by checking the anchors once the drain empties, since it
can't be seen cheaply where it happens. The sub-questions are settled too: a lost anchor keeps the
last rect *and warns* through `Tuile.logger`; a scrolled-away anchor is out of scope; the diagnostic
ignores reads made inside `perform_relayout`.

**The anchors that exist.** `Select#anchor` and `ComboBox#anchor` pass their own
`absolute_extent_rect`, and so does the menu bar's first panel (`Cascade#show`). `Cascade#push_beside`
passes a *parent dropdown's* `cursor_row_rect`. So an anchor is either a component in the content or
a row of another popup. `Anchored` should therefore hold something that returns a screen `Rect` when
asked: a component (read as `absolute_extent_rect`) or a proc (the cascade's row). Rows come from the
dropdown itself; width is `:anchor` or a number (`Select` measures its labels).

**The ordering problem is only for content anchors.**

- *Popup anchored to a popup* is solved by order within one pass. The pane places popups in stack
  order, so a submenu is placed after the panel it hangs from, and reads that panel's rect as
  assigned a moment earlier.
- *Popup anchored to content* is the real case. `flush_layout` walks pre-order, so the pane's
  `relayout` runs before the content subtree the anchor sits in, and reads the anchor's old absolute
  rect whenever the same settle moves the content: a resize, a timer adding a row above the form, a
  `Scroller` scrolling. The `ComboBox` dropdown is a non-modal `Overlay`, so focus and typing stay in
  the content while it is open, and a keystroke can reflow the content around it.

**Options:**

1. **A check once the drain empties** (preferred). The pane remembers the anchor rect each placement
   used. When the queue empties, `Screen#flush_layout` asks the pane whether any anchor now resolves
   differently. If one does, the pane marks itself and the loop drains again. This adds no new layout
   path: it is the ordinary rule ("an input to `relayout` changed, so mark"), with the change
   detected by polling because it can't be observed at its source. It ends after at most one extra
   round, because placing popups never changes the content. The cost is one `absolute_extent_rect`
   per anchored popup per settle, a walk to the root.
2. **Notify from the source.** `rect=` would check whether the moved component contains a registered
   anchor and mark the pane. It gives the same answer, but costs every rect change in every app.
   Rejected for the hot path.
3. **Place popups in a separate phase after the content.** The pane's `relayout` would place only
   `content`, and popups would get their own post-drain step. That's simpler to write, but it is
   exactly the "second layout path for popups" this idea exists to remove.
4. **Snapshot at open** (today). No ordering issue and no following: the dropdown stays where the
   field was.
5. **Close the popup when its anchor moves.** That's a behaviour policy, not a layout answer, and
   can be added on top of option 1 if wanted. I haven't checked which toolkits do this.

**Sub-questions:**

- *The anchor is detached or hidden while the popup is open.* `relayout` must not raise, so the
  placement keeps its last resolved rect. Closing the popup is the owner's job (`Select` and
  `ComboBox` already have `close_menu`). Is a hidden anchor worth a warning?
- *The anchor is scrolled out of view.* Its absolute rect is still computed, so the dropdown floats
  where the field would be. That's the same as today, and out of scope here.
- *The pane reads the anchor mid-drain, which may be stale.* That is the framework correcting
  itself within one flush; `design/ideas/stale-rect-diagnostic.md` carries what it means for a
  diagnostic.

`AGENTS.md` makes a sixth force-now `flush_layout` in `lib/` the falsifier of `D_deferred_layout`,
so the pane's `relayout` must not flush the content itself. Option 1 stays within that: it runs
inside the existing drain loop and adds no new flush.

### `Q_rect_writer` — how strictly is "only the parent, only in `relayout`" enforced?

**Settled (2026-09-22): `protected`, plus a runtime check that is always on.** `rect=` raises unless
the component's parent is the container whose `relayout` is running. **A component with no parent
raises too**, and the message says to hold it in an `Absolute` to measure a detached tree (option
(b) below): there is no root-only writer. The pane is the one parentless component that gets a
rect: the `Screen` stands in as its parent, marking itself as the running layouter while it sizes
the pane, so the check has one rule and no `is_a?(ScreenPane)` exception. Since `protected` answers
an outside caller with a bare `NoMethodError` before the check can speak, the same guidance goes in
`rect=`'s rdoc and in the CHANGELOG's migration line. The reasoning that got there:

**Audit.** Every `rect =` in `lib/` outside the overlays already runs while its parent's `relayout` is
running, including the ones in helpers it calls (`Window`'s footer, `FormItem`'s caption and message
labels). The remaining writers are the overlays (which this idea moves into the pane's pass),
`Screen` sizing the pane, and whoever sizes the root of a detached tree (the `flush_layout` rdoc
example, specs).

**What `protected` buys, and what it doesn't.**

- *It buys:* `rect=` disappears from the public API docs, and code outside any component (app
  bootstrap, a spec body) gets `NoMethodError`. That's the "only Tuile moves components" message,
  stated by the language.
- *It doesn't buy:* Ruby's `protected` admits any caller that is itself a `Component`, so a widget's
  `handle_key?` can still move a sibling, or itself.
- *Watch:* visibility is per definition, so an override (`Overlay#rect=`) must be declared protected
  again, or it quietly makes the writer public.

**The rule itself needs a runtime check.** `perform_relayout` records which container is running
(a thread-local, as the tree may have no screen, restored in an `ensure`). `rect=` on a component
**with a parent** raises unless that parent is the one running. That's one identity comparison, on
a write, not a read, so it can be **always on**, like `check_locked`, and not strict-mode only. The
message says what to do instead: "change its constraint (`Absolute#constrain`, `Box#constrain`,
`popup placement`)".

**Roots are the one legitimate outside writer**, because nothing is above them to run a `relayout`:

- `Screen` sizes the pane via `__send__` (it stands in for the pane's parent).
- A detached tree's root, sized in order to measure it:
  - (a) `__send__(:rect=, …)` in specs and the rdoc example: honest, but ugly.
  - (b) hold it in an `Absolute`, whose `Rect` constraints don't depend on its own size, so a bare
    detached `Absolute` places its children without a rect of its own. A clever trick, maybe too
    clever.
  - (c) a named root-only writer, e.g. `Component#root_rect=` (spelling open), which raises if the
    component has a parent. That keeps the one exception named and greppable.


### `Q_stale_diagnostic` — deferred

**Deferred (2026-09-22)** to `design/ideas/stale-rect-diagnostic.md`, so this idea can be built and
graduate without it. Nothing here depends on the diagnostic.

### `Q_order_of_work`

1. `Q_absolute_role`, then `mount_at` and the spec fixtures. **Done (2026-09-22):** `Absolute`
   takes a `Rect` per child and custom arithmetic subclasses `Layout`. Spec holders that only needed
   a container placing nothing became a bare `Layout`, which is exactly what the old `Absolute` was;
   the ones whose children get their `rect` written directly move to `Absolute` rects in step 3,
   when the guard finds them.
2. Popup placement into `ScreenPane#relayout`; the `rect=` override goes. **Done (2026-09-22):**
   `Overlay#open(placement)` with `Overlay::At` / `Centered` / `TopRight` and
   `ListDropdown::Anchored` (a component anchor is followed; rows are read live), the pane stores
   one per popup and places them in stacking order, `Screen#flush_layout` re-checks anchors once
   the drain empties, and a lost anchor keeps its rect and warns once. `Overlay#reposition` is now
   the request ("place me again"), `declared_size_in` is the size a placement reads, and
   `Popup#center` is gone. Left for graduation: the older `D_` entries that describe
   `reposition` as it was (`D_overlay`, `D_notification`, `D_confirm_window` history).
3. `Q_rect_writer`. **Done (2026-09-22):** `rect=` is protected and `check_placer` raises unless
   the parent's `perform_relayout` is running (a thread-local; `Screen` places the pane). The three
   `rect=` overrides became `handle_rect_changed(old_rect)`, because Ruby lets a `protected`
   override be called only from its own class, which the parent is not. `Absolute#add`'s rect
   became optional, keeping the child's current one; the spec suite goes through a `place` helper,
   and `FakeScreen#resize_terminal` replaced assigning the pane a rect.

These are one breaking change, built from `master`. The parked `strict-layout-diagnostic` branch is
not a prerequisite; its fate is `design/ideas/stale-rect-diagnostic.md`'s. On graduation the principle needs a `D_` entry of its own, and
`D_relayout`'s popup bullet and the `ScreenPane#rect=` rdoc get rewritten.

## Related

`D_relayout` (the rule and the bullet this overturns), `D_deferred_layout`, `D_declared_size`,
`D_tree_api`, `D_box_layouts`, `D_popup_open`. `design/ideas/per-child-attribute-map.md`: this adds
`Absolute` and `ScreenPane` as the third and fourth hand-rolled maps, which is the count that file
said to revisit at. `design/ideas/content-height.md`: a measured placement is a child answering its
parent's query, the same shape that file argues about.
