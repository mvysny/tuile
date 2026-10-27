# Look-and-feel — how a component kind is drawn, orthogonal to the hierarchy

**Status:** deferred to v2 by the owner (2026-10-27), not designed. Spun off the `Panel` /
`Dialog` refactor (`D_panel_dialog`), which fixed the component hierarchy and draws borders through
`BorderDrawerInt`, an internal helper class. This one may reuse it as-is, or may not.

**Problem:** with the hierarchy saying only what a component *is* (`D_panel_dialog`'s
principle), how it looks needs a home of its own. Today there is exactly one border and nothing
configures it.

## The shape so far

- **Orthogonal to the component hierarchy, the way `Theme` is**: set once on the screen, applied
  everywhere, swapped as a whole. Per component kind, it would define what border the component has
  (glyphs, which edges, caption placement, or no border at all) and how big the insets are.
- **It can have its own hierarchy, organized around drawing needs** (a captioned border *is* a
  border). `cop`'s rule holds there too: a painter subclasses to be a kind of border, never
  `DialogLook < PanelLook` to share code. That would move the same smell one axis over.
- **Where it differs from `Theme`: it owns geometry.** `Theme` is ink only, so `theme=` is one
  invalidate-all *repaint*. Insets move the content rect, so swapping the look-and-feel is also an
  invalidate-all *relayout*. The theme rule, "read it at paint time, never
  cache it", becomes "read the look-and-feel in `relayout` and in `repaint`, never cache an inset".

## Open

- **`Q_laf_vs_theme`**: part of `Theme` (which today carries accents only: `D_bg_inherit`,
  `D_no_hint_color`) or a sibling object? Leaning: a sibling. Color stays `Theme`'s, since
  `active_border_color` is already an accent token. Shape and insets go to the look-and-feel,
  because they move geometry and `Theme` never does.
- **`Q_laf_helper_reuse`**: does `BorderDrawerInt` become the per-kind painter, or is it replaced?
  Being internal, it can change freely either way. Decide when this is designed, not before.
