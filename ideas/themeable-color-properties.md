# Themeable color properties (live theme-token symbols)

**Status:** parked, not decided. Split out of
`ideas/background-fill-color.md` (issue #1) while settling `bg_color`.
For now `bg_color` — and color setters generally — take a concrete
`Color` only; this note captures the debate for a later, framework-wide
decision. Not to be brainstormed further until then.

## The question

Should a color setter accept a **live theme-token symbol** —
`panel.bg_color = :panel_bg` — that stores the token and resolves it
against the current theme *at paint time*, in addition to a concrete
`Color`? (Distinct from `Color.coerce`'s existing symbol support, which
is only the 16 *named ANSI colors* and yields a fixed `Color` — no theme
tracking.)

## Motivation (author's case)

- **Don't set the color twice.** Today an app that wants a theme-tracked
  color sets it once as a concrete `Color` *and* re-sets it in an
  `on_theme_changed` block — every time, for every color. `bg_color =
  :panel_bg` would "handle the theming part for me": pick a color from
  the theme palette and forget it; no need to think about terminal
  color-scheme flips.
- **`bg_color` is a natural fit** because it is resolved *live* at paint
  via `effective_bg_color`, not baked at construction. So a symbol-valued
  `bg_color` would auto-track light/dark flips with **zero
  `on_theme_changed` boilerplate** — the paint re-resolves the token each
  frame, exactly as framework chrome already does with theme tokens.
  (This is the strongest point, and it does *not* fall to the "caches a
  theme value in an ivar" objection — that concern is about storing a
  *resolved* color, e.g. TextField's well, not about storing a token
  resolved late.)

## Objections (framework-consistency case)

1. **Second theming channel.** Tuile has two kinds of color by design:
   theme tokens read live by chrome, and concrete Colors baked into app
   content (rebuilt in `on_theme_changed`). A live-symbol setter adds a
   third: a slot that's sometimes a token, sometimes a color, with a
   resolution rule threaded through the paint path.
2. **Leans toward the banned global bg token.** AGENTS.md refuses a
   global bg/fg token (non-accent cells inherit the terminal default).
   First-class `bg_color = :symbol` invites a *built-in* `:background`
   token next — the thing that stance exists to prevent. (Mitigated if
   symbols may only name an app's *custom* tokens.)
3. **Fail-fast** — *rebutted*: the setter can validate the token against
   the theme eagerly, or take a `ThemeColor` Data wrapper, so a typo
   fails at assignment, not deep in `repaint`.
4. **Redundant / inconsistent** — *partly rebutted*: yes, the custom-token
   + `on_theme_changed` pattern already exists and is what every other
   content color uses, so symbols add a second way to do it — but that
   second way is precisely the ergonomic win, and it needs *no* hook,
   unlike baked content.

## The bigger, riskier extension

The author's further intuition: push theme-awareness **into
`StyledString`** so a color never has to be set twice anywhere. This is a
much heavier lift than a symbol-valued `bg_color`, because it collides
head-on with StyledString's load-bearing invariants — pure frozen value
type, memoized `to_ansi`, the `parse(to_ansi(x)) == x` round-trip, and
zero `Screen`/theme dependency. Treat as a separate, higher-risk
sub-question; a themeable `bg_color` does **not** require it.

## Disposition

- **Now:** `bg_color` (and color setters) take a concrete `Color` only.
  Theme-tracking is the app's job via a custom token + `on_theme_changed`.
- **Later:** if the double-set boilerplate proves painful *across many
  properties*, revisit — but as a **general themeable-property
  mechanism** applied uniformly (symbol or `ThemeColor` resolved live at
  paint), not a special case welded onto one setter. Same "re-grow
  deliberately, not by accident" discipline as the top-down-layout rule.
  The StyledString-knows-themes variant is a distinct, heavier decision.
