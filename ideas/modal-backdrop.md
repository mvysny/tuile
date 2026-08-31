# Modal backdrop — dim the content under a popup, or cast a shadow

**Status:** seed, 2026-08-31. Deliberately not brainstormed yet; spun off from
`ideas/confirm-dialog.md`'s sizing question.

**The problem.** A modal `Popup` floats over the tiled content with no visual
separation beyond its own border: the content underneath is neither dimmed nor
shadowed. A small popup — a `ConfirmWindow` measuring a one-line "Overwrite?" —
can sit in the middle of a busy screen and simply not be noticed.

**The two candidate treatments** (every GUI stack ships at least one):

- **Dim/tint** the non-popup cells under the topmost modal.
- **A drop shadow** — a one-cell dark offset under/right of the popup box.

**Hooks that exist today, for whoever picks this up:** `Screen#repaint`
already partitions tiled vs. popup subtrees and repaints popups on top, so a
dim pass has a natural slot between the two. Terminal cells are opaque
(`D_bg_inherit`), so "dim" means restyling cells, not compositing — and
`Color` has no darken/blend operation yet, which a dim factor would need.

**Open when picked up:** flush-time transform in `Buffer` vs. repaint-time
style override in components; does a shadow belong to `Overlay` or only
`Popup`; interaction with themes and with the terminal-default (unset) bg.
