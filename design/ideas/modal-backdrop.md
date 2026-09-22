# Modal backdrop — dim the content under a popup, or cast a shadow

**Status:** seed, not brainstormed. Spun off `D_confirm_window`, whose sizing ruled that a tiny
yes/no box lost on a busy screen "is really a backdrop problem" — so `ConfirmWindow` has no size floor.

**Problem:** a modal `Popup` is separated from the tiled content only by its own border; a one-line
`ConfirmWindow` mid-screen can go unnoticed.

**Candidates** (every GUI stack ships at least one):
- **dim / tint** every non-popup cell under the topmost modal (`ScreenPane#modal_popup`);
- **drop shadow** — a one-cell dark offset below and right of the box.

**What exists:**
- `Screen#repaint` collects the tiled layer, then appends popups in stacking order — a dim pass has
  a natural slot between them.
- Cells are opaque (`D_bg_inherit`), so "dim" restyles cells; there is no compositing.
- `Color` has no darken / blend yet, which a dim factor needs.
- SGR 2 (faint) is a cheaper dim, but `Style` doesn't model it — `D_inverse` declined it until a
  consumer appears; this would be one.

## Open

- **`Q_backdrop_site`** — a flush-time transform in `Buffer` vs. a repaint-time style override.
  (`D_color_depth` makes `Buffer#flush` the sole quantization point; a dim there would sit beside it.)
- **`Q_shadow_owner`** — does a shadow belong to `Overlay` or only `Popup` (`modal?` is `true` only
  on `Popup`)?
- **`Q_backdrop_theme`** — interaction with themes and with the terminal-default (unset) bg, which
  has no color to darken.

## Related

`D_confirm_window`, `D_bg_inherit`, `D_inverse`, `D_color_depth`.
