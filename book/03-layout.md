# 3. Layout: the parent sets the size

**Status: stub. Written against the target design.**

The heart of Tuile's design, and the chapter with the most to say. It
argues *why* layout is top-down, absolute, and integer — and why that's
not a limitation but the correct fit for a character grid. This chapter
graduates the user-facing half of `ideas/simpler-layouting.md`: write
it against that target design (no `content_size` channel, `Popup#size=`,
`footer_text=`), **not** the current pre-0.9.0 API.

Will cover:

- The rule: a parent assigns its children's `rect`; a component never
  says how big it wants to be. Top-down, absolute integer coordinates.
- **Why simple layouting is enough** — the C64 argument, rewritten for
  a reader: a TUI's canvas is a discrete grid of known size, so the
  min/pref/max negotiation and constraint solvers of desktop/web
  toolkits are solving a problem ("I don't know my output device") a
  character grid doesn't have. Coarse + fixed + every-cell-visible
  makes explicit hand-placement the *better* mode.
- Why *enough*: cell budget × legibility caps a TUI at a handful of
  dense panes; the hard real TUIs (tmux, k9s, lazygit) are all nested
  rectangular splits, never flex/Cassowary.
- `Layout::Absolute` and overriding `rect=` to position children;
  ratios resolve to exact integers, not a solve.
- `Fraction` — sugar for sizing a popup against the screen (½×½
  default, resize-aware); the one place a child is auto-sized against
  its parent. Not a universal primitive.
- Resize as a *discrete recompute* on `SIGWINCH`, not continuous reflow.
- Geometry primitives: `Point`, `Size`, `Rect` (frozen value types,
  half-open edges) — introduced here in service of positioning.
