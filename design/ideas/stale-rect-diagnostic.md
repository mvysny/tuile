# Can the stale-rect diagnostic report only reads that were really stale?

**Status:** deferred, 2026-09-22. Split out of the brainstorm that made every rect the parent's
`relayout`'s to assign (`D_relayout`, landed the same day), which reached this question and parked
it. Nothing here is decided.

## Where things stand

The `strict-layout-diagnostic` branch (commits `26a1deb`, `bbf0e32`, `6103b3b`) adds
`Tuile.strict_layout`: a `Component#rect` read made while an ancestor owes a `relayout` reports
itself, raising by default under a `FakeScreen`. Its predicate is a guess (a dirty ancestor means
everything below it is stale). `D_strict_layout` on that branch has the measurements.

**Merged with `master` after `D_relayout` (2026-09-22)**, which decided `Q_branch_fate` below as
"keep the branch". The merge dropped two of the three special cases: `places_child?` (the pane places
its popups now) and `relayout_assigns_rects?` (`Absolute` has a `relayout`). What is left is the plain
dirty-ancestor walk plus `StrictLayout::PLUMBING`. On the merged suite that reported exactly three
reads, fewer than feared:

- `absolute_spec` "moves the child on the next settle, not before" and `overlay_spec` "moves on the
  next settle when the placement changes": both are deliberately unsettled, so they are now wrapped
  in `without_strict_layout`.
- `strict_layout_spec` "says nothing about the tree under an open popup": the false alarm this
  question is about. It is `pending` now.

The branch's `check_parent` commit (an overlay belongs only on the popup stack) held up. It made
`overlay_spec`'s "closed overlay is moved" example impossible (nothing can move a closed overlay
any more), and that example was deleted.

## `Q_stale_diagnostic` — report a stale read after the settle, not at the read

The branch's diagnostic guesses: a dirty ancestor means everything below it is stale. The settle is
the only code that knows which rects change, and under the new model pointless-but-honest marks get
*more* common (every popup open marks the pane), so the guess gets worse. Instead:

1. A read under a dirty ancestor records the component, the value it got, and `caller_locations`.
   Only suspect reads pay for the backtrace.
2. When `flush_layout` drains, each recorded component whose rect changed is reported, with its read
   site. The rest are dropped.

This removes every carve-out the branch measured: a read under a pointless mark is silent because
the value holds, and `StrictLayout::PLUMBING` probably goes, because a framework read that turns out
stale is a framework bug worth seeing. The costs:

- **The report arrives at the settle, not the read.** The backtrace points at `settle`, a gesture or
  `repaint`, so the read site has to be in the message. An example whose own assertion fails first
  shows the misleading diff before the diagnostic (RSpec reports both if an `after` hook raises).
- **A later mutation in the same turn can produce a false report.** Code reads a rect that happens
  to be right, then moves something, then settles.
- **A tree that is never flushed is never checked**, which is fine: there is nothing to compare
  against.

**Further points (2026-09-22):**

- **An absolute read needs an absolute comparison.** `absolute_rect`, `absolute_extent_rect`,
  `to_screen` and `to_local` can be stale while the component's own `rect` is not: the parent moved
  and the child kept its local rect. So the record keeps what the read *used*, local or absolute,
  and the settle compares that.
- **Keep the ancestor walk as the filter, not the verdict.** "Any ancestor is dirty" decides only
  whether a read is *recorded*; the settle decides whether it is *reported*. It works on a detached
  tree too, where there is no screen queue to ask. The branch's two special cases,
  `relayout_assigns_rects?` and `places_child?`, are unnecessary then: an imprecise filter only
  costs a record that gets dropped.
- **`PLUMBING` goes.** `Select` no longer reads its own rect when opening; the pane reads the anchor
  inside its pass, which is skipped (next point). Any other framework read
  that turns out stale is a framework bug worth reporting.
- **Record the first suspect read per component and kind per turn**, so a loop over one rect
  produces one report, naming the first site.
- **The later-mutation false report is accepted, with the message saying exactly what happened**:
  "read while X owed a relayout; the next settle changed it from A to B". Reading in the middle of
  a configuration is the smell either way.
- **A read never followed by a settle** goes unchecked in an example that ends right after it.
  `FakeScreen` could run a final flush-and-verify in `Screen.close`. Is that worth it, given the
  example's own assertion usually fails first?
- **Keep the branch's surface:** `Tuile.strict_layout` (`:raise` / `:warn` / `false`, `:raise` by
  default under a `FakeScreen`), `Tuile.without_strict_layout`, and the prepend so an app's `rect`
  stays a bare `attr_reader`.
- **Reads made inside `perform_relayout` are not recorded.** The pane reads an anchored popup's
  anchor mid-drain, and the drain corrects it (the post-drain anchor check, `D_relayout`).
  Recording it would report the framework correcting itself.

## `Q_branch_fate`

Answered by the merge: the branch continues and its predicate gets reworked in place.

## Related

`D_deferred_layout` (the residue this answers), `D_relayout`, the branch's `D_strict_layout`.
