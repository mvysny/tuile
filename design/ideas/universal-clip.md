# Clipping every component's children, by default

**Status:** **staging step 1 built, 2026-09-20**; step 2 (culling) open, which is
all that keeps this file alive. **Reopened and reversed `Q_clip_universal`** in
`design/ideas/scroller.md`, which resolved to opt-in one day earlier and shipped
that way as `D_clip`. `clip_rect` itself stayed exactly as built — the field, the
fold, the canvas clip, the cursor guard — and only its *default* changed, from
`nil` to `local_rect`.

Everything `D_clip` shipped is unreleased (`CHANGELOG.md` `[Unreleased]`), so this
landed as a revision of those entries rather than a breaking change.

**Graduate this file when step 2 lands or is declined** — `D_clip` already carries
the argument, the cost and the short-circuit refusal, so what is left here is the
culling design and the four open questions below.

## What reopened it

`D_clip`'s why-not clause rests on two claims. Both are wrong.

**The debuggability claim is backwards.** It reads:

> it turns a loud bug (a widget visibly corrupting its neighbour) into a silent
> one (a widget truncated for no visible reason)

A truncated widget is *self-identifying*: you know which component it is, you can
print its rect, and the bug is local to it. A corrupting widget is not — you see
garbage and have to bisect the tree to find the writer. Truncation is the bug
with a return address, so the asymmetry runs the other way.

**The provenance is misattributed.** The same clause says *"as Qt and the browser
do"*, then names the counter-argument *"the `overflow: visible` argument"*. But
`overflow: visible` is the browser's **default** — the browser does not clip. The
sentence enlists the browser as a clipper and then borrows the browser's
non-clipping default as the reason not to clip. `R_paint_context`, this project's
own recorded survey, says the premise plainly: Swing's `g.create(cx, cy, cw, ch)`
*"translates and clips in one call"*, Android's `ViewGroup#drawChild` wraps
`View#draw` in `save`/`translate`/`clipRect`/`restore`. Universal child clipping
is the near-unanimous answer among the toolkits already surveyed here.

## The three benefits are priced separately

`D_clip` weighed only the third, which is the expensive one.

| | what it needs | cost |
|---|---|---|
| **(i)** correctness for deliberate overflow | a clip wherever overflow exists | cheap |
| **(ii)** culling — never paint what no cell can show | one term in a walk that already runs | ~free |
| **(iii)** mechanical anti-corruption for buggy widgets | a live clip on every write | the 54 objects below |

**(i) makes overflow expressible, not just survivable.** Today *"a component must
not draw outside its rect"* is convention, not mechanism: nothing stops a negative
`rect.top`, layouts simply never produce one. Under a clip, a parent may
deliberately hand out more than it shows — a `Scroller`'s content box, an
absolute layout placing a child at `top: -5`, any viewport. The child needs to
know nothing about it, which is the point: a `Layout::Vertical` of 40 one-row
children positions all 40 exactly as it always did.

**(ii) is the argument nobody made.** It appears nowhere in `design/` except as an
owed bonus inside `scroller.md`, scoped to opt-in clipping. Made universal it
pays for the fold outright: `Screen#repaint`'s drain filter already walks the
ancestor chain per invalidated component,

```ruby
blocked = blocked.parent while blocked && !blocked.rect.empty? && blocked.visible?
```

and `visible?` was added to that loop as — the code's own words — *"one more term
in the same AND"*. "My rect misses my effective clip entirely" is the natural
third term, on a walk already paid for, needing only a running offset it would
accumulate anyway. Because the default `repaint` re-invalidates its children,
culled subtrees prune over successive drain iterations with no new recursion.
For the 40-row Vertical that is ~35 children never painted, ~1 ms against ~0.27 ms
of folds; at 1000 rows it is O(content) → O(viewport).

**It culls paint, not layout.** A container must still assign every child a rect
on every pass (`D_empty_ancestor`), so a 1000-row Vertical still does 1000 rect
assignments per scroll. This is the cheap half of virtualization and must not be
sold as the whole of it — `D_list_items` remains the answer to "a lot of rows".

## Measurements

`benchmark/clip.rb`, Ruby 3.3, depth 7, 120×40 buffer. Re-run it before trusting
these; they are one machine's.

**Per write, the clip containing every write** — the case universal clipping hits
almost always:

| | clip = nil | clip = whole screen | |
|---|---|---|---|
| `set_text` ×40 rows | 966 µs/op | 995 µs/op | **1.03×** |
| `fill` whole screen | 433 µs/op | 437 µs/op | **1.01×** |

Unmeasurable. The backend painting cells dominates, and `display_width` — which
`write_clipped_text` adds per call, and which looked like the risk — measures
0.048 µs against a 24 µs `set_text`. **`D_clip`'s "charges every app a chain walk
on every draw call" is loose twice over**: the walk is not per draw call, and the
per-draw cost does not exist.

**Per component, `effective_clip`:**

| | µs/op | objects allocated |
|---|---|---|
| no ancestor declares (today) | 0.46 | **0** |
| every ancestor declares | 7.36 (**16×**) | **54** |

This is the real cost, and the walk is not it: `canvas_for` already makes two
unconditional upward walks (`to_screen`, `effective_bg_color`) and the nil fold
rides along at 0.46 µs. The blowup is arithmetic and allocation per level — a
`Point`, a `moved_by` `Rect`, an `intersect` `Rect`, all immediately garbage.
It is charged per component regardless of how little that component paints, so a
`Label` painting one row (~24 µs) takes a ~28% tax, on exactly the leaf-heavy
trees Tuile is made of.

## Open questions

`Q_containment_shortcircuit` — **resolved: declined, and `D_clip` says why.**
If every ancestor fully contains its child, the folded clip provably cannot cut
anything *and the fold can return `nil`* — which is the overwhelmingly common
case and kills the 54 objects outright. But the proof holds only *if the child
obeys its own rect*, which is precisely what (iii) wanted enforced. So the
short-circuit buys (i) and (ii) at nearly no cost while giving (iii) back. The
54 objects are paid instead, because (iii) is what the change is *for*. A debug
mode (`Tuile.strict_clip`, on under `rake check`) was the way to have both, and
`Q_contract_spec_goes_dark` resolving on its own took away its one caller.

Still open as a pure optimization, with no semantic cost: **memoize `clip_rect`
per component**, invalidated in `rect=`, and fold into a reused mutable
accumulator. `scroller.md` records that memoizing the *fold* turned out moot —
a different measurement that does not settle this one.

`Q_contract_spec_goes_dark` — **resolved: it does not.** The worry was that
`component_contract_spec`'s stray sweep (`spec/tuile/component_contract_spec.rb:235`)
would pass vacuously once the canvas eats strays. It does not, and the reason is
worth keeping: `paint` attaches the component under test as `screen.content`, so
its only ancestor is the full-screen `ScreenPane`, and `contract_rect` is inset
on all four sides. A stray therefore lands *inside* the only clip above it and
outside the component's own rect — exactly what the sweep looks for. The suite
confirms it: the flip left that context green with no change. **This holds only
while the component under test is a pane child** — parent it under anything
smaller and the sweep really does go dark.

`Q_cursor_overhang` — **resolved: hidden, and now pinned.** A caret outside the
box its component was given is a cell nothing can show, so `Screen#cursor_position`
answers `nil`. `screen_spec`'s "hides a cursor the component's own rect cannot
show" is the new case; the popup preference case moved its probe inside the box,
since its old 99,33 was testing the overhang by accident.

`Q_empty_ancestor_clips_to_nothing` — **resolved by construction, and it broke
eight specs worth reading.** A parent with no rect assigned has an empty
`local_rect`, so it now clips its subtree to nothing. That is what
`D_empty_ancestor` always said a collapsed subtree means, and `Screen#repaint`'s
drain filter has dropped such subtrees all along — but eight bg-inheritance specs
built a bare `Layout::Absolute`, never laid it out, and called `repaint` directly,
bypassing the drain. They were asserting against a tree no layout would produce.
Fixed by laying the parent out. **A spec that parents a component and paints it
directly must now lay the parent out too**; nothing enforces that.

`Q_cull_reentry` — a culled component never paints, so whatever brings it back
into view must invalidate it. Scrolling reassigns rects and so invalidates the
subtree anyway; what is unverified is every *other* route back — `visible=`, a
constraint change, a resize. The drain filter is the single choke point, which is
the reason to put culling there and nowhere else.

## Docs fixed

~~All eight, in the same commit as step 1.~~ Kept as the record of what each one
used to assert, and as the list to re-check if step 2 changes any of them again.

- **`D_clip`, `decisions.md`** — the entry's question still stands but its answer
  is rewritten, not amended (tripwire: no "Superseded by", no strikethrough). Two
  specific repairs beyond the reversal: delete *"as Qt and the browser do"* or fix
  it to *"as Swing, Android and Qt do"*, and drop the `overflow: visible` citation
  entirely rather than re-pointing it. Its *"charges every app a chain walk on
  every draw call"* is measurably wrong and should become the per-component number.
  The parts that survive untouched: the backend-coordinate rationale, the
  field-not-backend rationale, the straddling-cluster policy, the cursor policy.
- **`design/ideas/scroller.md`** — `Q_clip_universal` reverses; the **Risks**
  entry *"Silent truncation … the reason `Q_clip_universal` resolved to opt-in"*
  reverses with it; **Staging** step 1's *"behaviour-neutral until something
  declares a `clip_rect`"* stops being true; the stage-3 drain-filter bonus is
  promoted to a reason for this change rather than an optimization with no caller.
  Note this file graduates on `Scroller` shipping — fold these in, don't outlive it.
- **`AGENTS.md`, Repaint** — *"A container handing out a rect it will not show in
  full declares a `clip_rect`; nothing else stops a write"* inverts: the clip is
  the default and `clip_rect` is what a container *widens or narrows*. The line
  above it, *"A component must not draw outside its `rect`"*, stays — it is still
  the contract every widget writes to; only the consequence of breaking it changes.
- **`book/02-repaint.md:141-145`** — *"there's no clipping to save you, so drawing
  out of bounds means drawing on someone else's cells"* becomes false, and the
  parenthetical demoting `clip_rect` to a scrolling-viewport opt-in with it. The
  chapter's rule survives; its *justification* has to change, and a learner should
  be told the clip catches them rather than that nothing does.
- **`Component#clip_rect` rdoc** — the default flips, and *"`nil` (the default) to
  impose none"* with it; `extent`'s mirror-image framing survives intact.
- **`Component#effective_clip` rdoc** — *"`nil` when no ancestor declares one —
  which is the reason a clip costs one nil test on the common paint path"* is the
  old bargain. What replaces it depends on `Q_containment_shortcircuit`.
- **`CHANGELOG.md` `[Unreleased]`** — revise the `Component#clip_rect` and
  `Canvas#clip` entries in place. Unreleased, so no `**Breaking:**` line is owed.
- **`D_visibility`'s why-not list** and **`Screen#repaint`'s rdoc** (`screen.rb:887`)
  both decline a `Component#paintable?` predicate. That reasoning holds and the
  culling term must go in the same `delete_if` rather than growing a public
  predicate — worth re-reading, not rewriting.

## Staging

1. ~~**The default flips.**~~ Done. `clip_rect` defaults to `local_rect`, both
   rdocs rewritten, and every doc above fixed in the same commit. No new API and
   no `**Breaking:**` line, the field being unreleased. Pinned by
   `component_spec`'s "keeps an overflowing child off its neighbours with no
   clip_rect anywhere" — `D_clip`'s own motivating failure, which blanks the menu
   bar with the old default and does not with the new one.
2. **The culling term** in `Screen#repaint`'s `delete_if`, with `Q_cull_reentry`'s
   routes covered by spec. **The only reason this file is still here.**

`Scroller` (this note's original caller) is unblocked by step 1 and needs nothing
from step 2.

## Risks

- ~~**`Q_contract_spec_goes_dark`**~~ — resolved above, with the condition that
  keeps it resolved.
- **A clipped app is a slower app, and nobody has measured a real one.** The
  numbers here are a synthetic depth-7 chain. Step 1 shipped without measuring
  `examples/file_commander.rb` or `sampler.rb`, which is the honest gap: the cost
  is charged per component on leaf-heavy trees, the shape Tuile encourages. Do
  this before step 2, so culling is judged against a real baseline rather than
  credited with paying for something nobody priced.
- **A spec that paints a parented component directly must lay the parent out.**
  `Q_empty_ancestor_clips_to_nothing` cost eight specs; nothing stops the ninth.
- **Culling and invalidation are the same bug surface.** A component that should
  have repainted and did not is the hardest failure in a retained tree to see,
  and step 2 adds a new way to reach it.

## Related

`D_clip` (the entry this reverses), `D_canvas` (the seam it rides on),
`D_extent` (the mirror `clip_rect` is drawn on, and the
forgetting-degrades-gracefully principle this change trades away),
`D_empty_ancestor` (rects are assigned regardless — why culling is paint-only),
`D_visibility` (the `paintable?` refusal culling must respect),
`D_repaint_cascade` (why a culled subtree prunes over drain iterations),
`D_component_contract` (the sweep `Q_contract_spec_goes_dark` is about),
`D_list_items` (the other, larger answer to "a lot of rows"),
`D_relative_rect` (the coordinate spaces the fold converts between),
`D_declared_size` (the bottom-up channel this does *not* reopen),
`R_paint_context` (the survey `D_clip` misread),
`design/ideas/scroller.md` (the caller, and the file carrying the reversed question),
`design/ideas/per-component-buffers.md` (the other answer to the same scroll cost).
