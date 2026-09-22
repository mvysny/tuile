# The focus accent — move `Button` / `Checkbox` / `Tabs` / `MenuBar` / `List` onto `bg.default_color`?

**Status:** measured 2026-09-01 and parked; the answer is (A) below. `D_bg_surface`
records the decision not to migrate; this file keeps the measurement and the missing guard.

## Today

Five widgets stomp `Theme#active_bg_color` over their content at paint:

```ruby
label = label.with_bg(screen.theme.active_bg_color) if active?   # button.rb:86, checkbox.rb:130
active? ? segment.with_bg(screen.theme.active_bg_color) : segment # tabs.rb:484 (menu_bar.rb:523 alike)
is_cursor ? base.with_bg(screen.theme.active_bg_color) : base    # list.rb:943
```

`bg.default_color = { active: Theme.ref(:active_bg_color) }` (no `:normal`, so unfocused
falls through to ambient) could express the per-component half.

## Measured on `Checkbox`

The migration nets **+2 lines** — these widgets have no well, so nothing is deleted
(unlike `AbstractStringField`, which lost its `#background`). The suite passed
(2787 examples, 0 failures), so neither change below was pinned.

Focused `Checkbox`, 20×1:

| case | original | migrated |
|---|---|---|
| caption span with `bg: BLUE` | `59, 59` — accent covers it | `59, :blue` — span punches a hole |
| `bg_color = 52` | `59, 59` — accent over the tint | `52, 52` — no focus shade at all |

## What it says

- **A surface is not an accent.** A surface is what cells sit on and is the app's to
  override (`bg_color` beats `bg.default_color`). An accent is a signal painted *over*,
  and must be unconditional — suppressible means unreliable.
- Row 1: `with_bg` is override-all, `under_bg` (what `Canvas#set_text` applies) is
  fill-unset (`D_bg_inherit`).
- Row 2: `Checkbox` has no caret, so a flat `bg_color` removes its only focus cue.
  `{ normal:, active: }` recovers it, but the default got worse.
- `Tabs`, `MenuBar`, `List` accent a *segment or row*; a per-component level can't
  express that. Only `Button` and `Checkbox` qualify, so migrating splits the family.

## Options

- **(A) Leave it, pin it.** The measurement says the status quo is right.
- **(B) Migrate `Button` + `Checkbox` only.** Both regressions, a split family. No.
- **(C) An accent layer as its own concept** — override-all, applied after the `bg`
  chain, on a `StyledString`, so it covers segments and rows too. A second colour channel;
  weigh against `D_theme_ref`'s "not a third color channel".
- **(D) Framework-painted focus** — `Screen` accents the focused extent. Needs per-widget
  opt-out (`TextArea`) and a framework paint pass the retained tree keeps out. No.

## The missing guard — do regardless

Still unpinned. In `checkbox_spec` and `button_spec`:
- the accent covers a caption span carrying its own **bg** (pins `with_bg`). `button_spec`'s
  "paints the highlight over them" uses an **fg**-only span, which `under_bg` passes too;
- `bg_color` on the widget does not suppress the accent.

That turns `D_bg_surface`'s "not migrated" from recorded to enforced; with it, the file
can graduate as (A).

## Related

`D_bg_surface`, `D_bg_inherit`, `D_boolean_fields` (extent arithmetic must not vary with
`bg_color`), `D_theme_ref`.
