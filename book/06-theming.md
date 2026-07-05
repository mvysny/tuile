# 6. Theming

**Status: stub.**

The runtime chapter on color. Explains the semantic-token model, how
Tuile follows the terminal's light/dark appearance, and how an app
themes itself durably. Assumes the repaint model (theme changes
invalidate the tree).

Will cover:

- `Theme` — a frozen value type of semantic color tokens, read at paint
  time (never cache theme values in ivars). Non-accent cells inherit the
  terminal's own fg/bg; there is no global bg/fg token.
- The rendering helpers (`active_bg`, `hint`, `input_bg`, …) and the
  raw `*_color` readers for `StyledString` work.
- Auto-detection at startup (`TerminalBackground.detect`: OSC 11 +
  COLORFGBG) and live OS appearance flips via mode 2031 — why detection
  must live in the constructor (the reply arrives on stdin the key
  thread owns).
- App theming: custom tokens (`theme[:token]`, `fg`/`bg`), a `Theme`
  subclass with one coloring method per token, and pairing dark/light
  variants in a `ThemeDef` assigned to `screen.theme_def=` — the durable
  way, surviving appearance flips where a bare `theme=` is transient.
- Reacting to changes: `on_theme_changed` for app-rendered content whose
  colors were baked in at construction (rebuild by re-running the render
  code); subclass vs. listener consumption.
