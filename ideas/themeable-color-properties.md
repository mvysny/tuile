# Themeable color properties (live theme-token symbols)

**Status:** *decided* (2026-07-23) — relax for `bg_color` **only**, as a
probe; see *Resolution* below. Pending implementation; this note graduates
(→ DECISIONS.md + AGENTS.md + book ch6) once it ships and settles. Split
off while settling `bg_color` (issue #1, decision `D-bg-inherit` in
`DECISIONS.md`).

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

## Resolution (2026-07-23)

Three facts from the code reframed the debate and tipped it to *yes, for
`bg_color`*:

1. **`bg_color` is the only app-settable color already resolved at paint.**
   Content colors (`Label#text`, `List#lines`, `TextView#text`) bake
   `Color`s into a frozen `StyledString` at construction and *must* stay on
   `on_theme_changed` (that's the StyledString round-trip/memoization wall).
   `bg_color` is a lone ivar read late through `effective_bg_color`, so a
   live ref there is **not a new resolution pass** — it changes what the
   existing resolution reads. One `is_a?` branch, nothing new in the paint
   loop.
2. **Not a "third channel" — it opens the *existing* live-chrome channel.**
   Chrome already reads tokens live at paint (`button.rb`, `window.rb`,
   `list.rb`, `text_input.rb` all read `screen.theme.*` in `repaint`). A
   ref-valued `bg_color` makes *app-set* bg behave like chrome. Unification,
   not proliferation.
3. **The banned global bg/fg token stays structurally unreachable.** `theme[]`
   is `custom.fetch`, so a ref can only ever name an app *custom* token —
   never a built-in chrome token, never a hypothetical `:background`. The
   "no global bg/fg token" invariant is orthogonal and fully intact.
   (Objection 2 above thus mostly evaporates.)

**Mechanism — `Theme::Ref`** (not a bare symbol): a bare symbol collides
with `Color.coerce`, where `:red`/`:blue` are the 16 named ANSI colors —
`bg_color = :blue` would be ambiguous. A tiny `Data.define(:name)` wrapper
disambiguates and gives fail-fast:

```ruby
Theme::Ref = Data.define(:name) { def resolve(theme) = theme[name] }
Theme.ref(:panel_bg)                     # factory
panel.bg_color = Theme.ref(:panel_bg)    # tracks light/dark flips, no hook
```

- `bg_color=` accepts `Color | Theme::Ref | nil`; a `Ref` is validated
  eagerly against `Screen.instance.theme` at assignment (KeyError at the
  call site, not deep in `repaint`); a non-`Ref` still passes through
  `Color.coerce`.
- `effective_bg_color` gains `own = own.resolve(screen.theme) if
  own.is_a?(Theme::Ref)` before the upward fallback. Downstream
  (`draw_line`/`under_bg`) still sees a plain `Color` — fully contained.
- `ThemeDef` already forbids mismatched custom-key sets across dark/light,
  so a scheme flip can't strand a `Ref`.

Naming: `Ref` chosen over `token`/`Var`/`ColorRef`/`Key` — honest about
being a late-bound reference, short, and future-proof if a theme ever holds
a non-color entry. (`Style*` rejected: collides with `StyledString::Style`.)

## Disposition

- **Now (this change):** `bg_color` accepts `Color | Theme::Ref | nil`.
  Theme-tracking for a background is `Theme.ref(:token)` — no hook.
- **Still baked + hook:** all content colors (`Label`/`List`/`TextView`),
  because StyledString can't carry a live ref without breaking its
  invariants. The StyledString-knows-themes variant remains a distinct,
  heavier, *unopened* decision.
- **Later:** if the probe proves out, revisit widening `Theme::Ref` to any
  other property that resolves at paint — but as the *same* general
  mechanism, never a per-setter special case ("re-grow deliberately").
