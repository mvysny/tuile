# 7. The component library

**Status: stub.**

A narrative tour of the shipped toolbox, framed around *when and why*
you reach for each component and what use-case it fits — walkthroughs
and examples, not a reference. The exact signatures stay in the rdoc;
this chapter links to them rather than restating them.

Will cover (each as when/why + a short example):

- `Label` — static one-liners; truncates, doesn't wrap (for wrapping,
  reach for `TextView`).
- `List` — scrollable lines, cursor variants (`None` / `Cursor` /
  `Limited`), `on_item_chosen`, auto-scroll.
- The text family: `TextField` (single line, real caret),
  `TextArea` (multi-line editor), `TextView` (read-only scrollable
  wrapped prose) — which to pick for what.
- `Window` — bordered frame with a content slot, optional footer and
  scrollbar.
- `Popup` — modal overlay sized top-down against the screen (see ch. 3);
  wraps any component.
- The window conveniences: `InfoWindow`, `PickerWindow`, `LogWindow`
  (+ wiring a logger through `LogWindow::IO`).
