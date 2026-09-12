# The focus accent — should `Button` / `Checkbox` / `Tabs` / `MenuBar` / `List` move onto `default_bg_color`?

**Status:** measured and parked, 2026-09-01. Spun off from `D_bg_surface`,
which introduced `Component#default_bg_color` and migrated the *well* widgets
(`AbstractStringField`, `Select`, `ComboBox`) onto it while explicitly leaving
this family alone. That note records the decision; this one records the
*measurement*, so whoever revisits it doesn't re-run the experiment.

## The question

Five widgets highlight themselves on focus by stomping a background onto their
painted content at repaint time:

```ruby
label = label.with_bg(screen.theme.active_bg_color) if active?   # Button, Checkbox
segment.with_bg(screen.theme.active_bg_color)                    # Tabs, MenuBar
is_cursor ? base.with_bg(screen.theme.active_bg_color) : base    # List
```

`default_bg_color` can express the per-component half of that —
`{ active: screen.theme.active_bg_color }`, or the allocation-free
`active? ? … : nil`, with no `:normal` key so an unfocused widget falls through
to the ambient. So: should it?

## Measured, not argued (Checkbox, 2026-09-01)

The migration was written and run. It is:

```diff
       label = (StyledString.plain(value ? "[x] " : "[ ] ") + caption).ellipsize(rect.width)
-      label = label.with_bg(screen.theme.active_bg_color) if active?
       draw_text(rect.left, rect.top, label)
     end
+
+    # @return [Color, nil]
+    def default_bg_color = active? ? screen.theme.active_bg_color : nil
```

**Net +2 lines.** Nothing is deleted, because these widgets have no *well* —
there is no reach-around-the-chain to remove, which is exactly what the
`AbstractStringField` migration did delete (`#background`). So it is not a
simplification.

**The whole suite passed: 2787 examples, 0 failures.** Both behavior changes
below are unpinned by any spec — see *The missing guard*.

Probed directly, migrated vs. original, on a focused `Checkbox` at 20×1:

| case | original | migrated |
|---|---|---|
| caption span carries `bg: BLUE` | `59, 59` — accent covers it | `59, :blue` — **the span survives** |
| `bg_color = 52` | `59, 59` — accent stomps the tint | `52, 52` — tint wins, no focus shade |

## What the measurement says

**A surface and an accent are different things, and the hook is only right for
one.** A *surface* is what your cells sit on; it is legitimately the app's to
override, which is the whole point of `bg_color` winning over
`default_bg_color`. An *accent* is a signal painted **over** whatever is there,
and it must be unconditional — the moment it can be selectively suppressed
(by a caption span, by an app tint) it stops being a reliable indicator.

Row 1 is therefore a regression: `with_bg` is override-all, `under_bg` (what
`draw_text` applies) is fill-unset, so a caption carrying its own background
punches a hole in the highlight.

Row 2 is worse than it looks: `Checkbox` paints no caret, so a flat `bg_color`
removes its only focus affordance. Recoverable with `{ normal:, active: }`, but
the *default* got worse. This is the same objection that made `Select` the
awkward case in `D_bg_surface` — there it was accepted because a `Select` really
does paint a well, and the flat surface is a real thing to want.

**And for three of the five it isn't even expressible.** `Tabs`, `MenuBar` and
`List` accent a *segment or row*, not the component. A per-component hook has
nothing to say about "the third tab" or "the cursor row". Only `Button` and
`Checkbox` are candidates at all, which makes a partial migration a
consistency *loss*, not a gain.

## Options, when this is picked up

- **(A) Leave it, pin it.** The status quo plus the specs below. Cheapest, and
  the measurement above says the status quo is right.
- **(B) Migrate `Button` + `Checkbox` only.** Costs +4 lines, splits the family
  three ways, and takes both regressions. Hard to justify on this evidence.
- **(C) Name the accent as its own concept.** The honest generalisation: a
  paint-time `over_bg` / accent layer that is *not* part of the `bg_color`
  chain and is applied after it, with an explicit `with_bg` (override-all)
  contract. That would cover all five *and* the segment/row cases, because the
  layer is applied to a `StyledString` rather than declared per component. It
  is a second colour channel, though — weigh against `D_theme_ref`'s "not a
  third colour channel" reasoning before adding one.
- **(D) Make focus indication a framework concern.** `Screen` knows the focus
  chain; it could accent the focused component's extent centrally. Almost
  certainly wrong — it would need per-widget opt-out (a focused `TextArea` must
  not have its whole rect stomped) and reintroduces a framework-owned paint
  pass the top-down layout rule keeps out.

## The missing guard (do this regardless of the outcome)

Neither behavior in the table is asserted anywhere, which is how a future
migration would land silently. `checkbox_spec` and `button_spec` want:

- the focus accent covers a caption span that carries its own background
  (pins `with_bg`, not `under_bg`);
- `bg_color` set on the widget does **not** suppress the focus accent
  (pins the accent as unconditional).

Eight lines each, and they convert `D_bg_surface`'s "deliberately not migrated"
from recorded to enforced.

## Related

`D_bg_surface` (the chain, the state map, the surface/accent line),
`D_bg_inherit` (`under_bg` vs `with_bg`), `D_boolean_fields` (why the extent
arithmetic must not vary with `bg_color`), `D_theme_ref` (why there is not a
third colour channel).
