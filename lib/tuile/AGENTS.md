# AGENTS.md — `lib/tuile/`

The runtime's file map, loaded beside the root file when work touches this directory. The
cross-cutting seams — the tree, repaint, the UI thread, the key ladder, the theme, locale and
background chains, glyph width — are the root `AGENTS.md`'s and are not restated here; per-symbol
truth is each class's rdoc, and the wiring and flows are `design/architecture.md`. Cap 10 KB.

## Seams

- **`ScreenPane#detach_all` is deliberately not generic** — a `Component#remove_all_children` would
  let a slot container empty `@children` while `#content` / `#footer` still pointed at detached
  components, the desync the tree API prevents. Nor is it named `close`, which already means
  "remove *me* from the pane". See `D_attach_hooks`.
- **`Screen#hidden?` is private and spelled at its two call sites** (the drain filter and
  `focused=`) — don't promote it to a public `Component#shown?`; walks prune at the hidden root and
  need none. See `D_visibility`.
- **A `Theme::Ref` background stays current only because `theme=` invalidates the whole tree** — if
  that fan-out is ever pruned, `Theme::Ref` backgrounds must still be invalidated on a theme change
  (guarded in `screen_spec`). The setter validates eagerly, raising `KeyError` at assignment.
  See `D_theme_ref`.
- **`ThemeDef.default` and `VerticalScrollBar.handle_char` / `.track_char` are the reassignable
  app-globals** — an app sets them once; a spec that changes one restores it. See `D_scrollbar_ink`.

## Files

- `ansi.rb` — escape constants: `RESET`, `BEL`, the synchronized-output pair
- `buffer.rb` — the back buffer of styled cells (+ `Cell`); flushes the minimal diff, quantizes
- `color.rb` — named / 256-palette / RGB color; factories, `coerce`, `quantize`
- `color_depth.rb` — env-only truecolor / palette256 / ansi16 probe; `TUILE_COLOR_DEPTH` overrides
- `component.rb` — the base: tree, rect, focus, paint helpers, the background chain
- `event_queue.rb` — the queue, the key thread, the `SIGWINCH` trap, and the nested event types
- `fake_event_queue.rb` — synchronous test double; never runs a loop
- `fake_screen.rb` — in-memory `Screen`: captured `prints`, pinned depth and locale
- `final.rb` — the `final` keyword Ruby lacks: mark, then verify at the first `new`
- `fraction.rb` — a width/height ratio resolved against a `Size`; `Popup` sizing only
- `keys.rb` — key constants, `getkey`, the paste reader and its normalization
- `locale.rb` — frozen formatting conventions; `ISO`, `.system`, the format lexer and validators
- `mouse_event.rb` — parses X10 mouse reports
- `point.rb`, `size.rb`, `rect.rb` — frozen `Data.define` geometry value types
- `screen.rb` — the singleton runtime: loop, dispatch, repaint drain, lifecycle, detection
- `screen_pane.rb` — the structural root of the tree: content, the popup stack, focus repair
- `styled_string.rb` — span-based styled text: parse / slice / wrap / truncate / measure
- `terminal_background.rb` — the OSC 11 and `COLORFGBG` light/dark probe
- `testing.rb` — test-time component locators: `find` / `get` / `dump`
- `theme.rb` — semantic accent tokens; `DARK` / `LIGHT`, and `Theme::Ref`
- `theme_def.rb` — the dark/light `Theme` pair an app installs; `ThemeDef.default` seeds new screens
- `version.rb` — the `VERSION` constant
- `vertical_scroll_bar.rb` — the character-grid scrollbar; a rendering helper, not a `Component`
- `component/` — the widget set; see `component/AGENTS.md`
