# TextField placeholder — a hint painted into the empty buffer

**Status:** filed 2026-09-04, spun off from `ideas/date-field.md`. Wanted there
first (a date field must tell the user *which* of its formats it writes back —
information available nowhere else), but it is a general text-input affordance
and should not ship as a private `DateField` trick.

Agreed 2026-09-04: the plain `String`, the deliberately barely-visible ink, and
"this is not a caption". The ink section below changed as a result — `hint_color`
is *out*. Also settled that round: it **ellipsizes**, the composed fields **do**
get forwarders (hence a `HasPlaceholder` mixin), an invalid field **still shows
it**, `TextArea` waits until something wants it, and the ink is **a gray first**
with `dim` held as the fallback. What remains open is the shade and the two
questions the new mixin creates.

**The proposal.** A `TextField` carries an optional `placeholder` String, painted
in its own cells while the buffer is empty, in a deliberately barely-visible ink
(see "The ink" — *not* `Theme#hint_color`). It is paint-only: it never enters
`text`, never fires `on_change`, and does not move the caret.

```ruby
field = Component::TextField.new
field.placeholder = "dd.mm.yyyy"
field.text.empty?   # => true — the placeholder is not content
```

## The trap that shapes the whole thing: it is *not* `display_text`

`display_text` looks like the seam and is the wrong one. Its contract is **one
display character per `text` character, in order** (`text_field.rb`), because
`column_at`, `index_at`, `visible_text` and `adjust_left_column` all measure it
as the rendering of the buffer. An empty buffer showing ten glyphs of
placeholder breaks that in the most visible way possible: `cursor_position`
would park the caret past the hint instead of at column 0.

So the placeholder is a **branch in `repaint`**, beside `visible_text`, not a
substitution underneath it. Roughly:

```ruby
def repaint
  return if rect.empty?

  return draw_text(rect.left, rect.top, StyledString.plain(visible_text)) unless show_placeholder?

  draw_text(rect.left, rect.top, placeholder_row)   # NB: rect.width wide — see below
end
```

Four things that branch owes:

- **Pad the row to `rect.width`.** This is the one that bites: `TextField#repaint`
  does not call `super`, so nothing else clears the rect — `visible_text` pads
  itself with spaces (`" " * (rect.width - width)`) and *that padded row is the
  well*. A placeholder branch painting only the hint's own columns leaves the
  rest of the field unpainted: stale glyphs from whatever was there before, and
  the tint stopping halfway across a field that should read as one well. So
  `ellipsize(rect.width)` **and then** pad back out to `rect.width`.

- **Go through `draw_text`.** It is the background choke point
  (`effective_bg_color` via `under_bg`); `screen.buffer.set_text` would drop the
  field's well and its `bg_color` inheritance.
- **Pad and shorten by *columns*, not characters** — `StyledString#ellipsize`,
  never `[0, rect.width]`. Same rule as `visible_text`. (Ellipsize rather than
  clip; ruled below.)
- **Resolve the ink at paint time**, whichever token it ends up being. Never
  cache it in an ivar; a `theme=` restyles through one invalidate-all pass and a
  cached color strands on the old scheme.

Nothing else in the class changes: with an empty buffer `caret` is 0 and
`left_column` is 0, so the cursor lands on `rect.left` on its own and the
scrolling machinery has nothing to do.

## Rulings worth making up front

- **A plain `String`, not a `StyledString`.** Two reasons, and the second is the
  durable one. Mechanically: the ink is the framework's, so an app-supplied
  `StyledString` would bake its colors at construction and need an
  `on_theme_changed` rebuild to survive a theme flip — the trap `D_theme_ref` and
  the theme rules exist to keep off chrome. By intent: the ink is *deliberately*
  barely visible (see below), so a per-app color is not a missing knob, it is a
  knob for defeating the design. If a real need for styled placeholder text ever
  appears it is a separate argument.
- **The condition is `text.empty?` alone — no focus term.** Browsers used to
  hide the placeholder on focus and HTML5 stopped; for this component the
  argument is stronger than convention, because the `DateField` case *needs* the
  format hint precisely while the user is typing into the field. One condition
  also means no `on_focus` bookkeeping (a focus change already repaints — the
  well switches on `active?`).
- **Paint-only, in every direction.** Not in `text`, `value`, `empty?`,
  `on_change`, a paste, or `max_text_length`'s budget. That asymmetry *is* the
  feature — a placeholder that lived in the buffer would be a default value, and
  a form saving it would write "dd.mm.yyyy" to the database.
- **`PasswordField` inherits it and should.** "password" under an empty masked
  field is the standard look, and the mask only ever applies to buffer content.

## Where it lives — `TextField`, and why not `AbstractStringField`

The state (`@placeholder`, plus the `text.empty?` predicate) is generic; the
paint is not — `TextField` writes one windowed row, `TextArea` wraps into a
viewport. Putting the accessor on the shared base and painting it in only one
subclass ships a public setter that is silently inert on the other, which is
worse than not having it.

So: **`TextField` only for v1** (which is also the whole `DateField` need, and
`PasswordField` and every composed field ride along), and if `TextArea` turns out
to want one, the accessor moves up to `AbstractStringField` at that point with
both paints written. Do not pre-build the base for one caller.

## The seam: a `HasPlaceholder` mixin, forwarded by the composed fields

**Composed fields carry their own `placeholder` / `placeholder=`.** An app using
an `IntegerField` should not have to know it is a `TextField` in a trenchcoat;
`content.placeholder = …` leaks the implementation. So `IntegerField`,
`FloatField`, `BigDecimalField` and `ComboBox` each forward to their inner field,
and the contract lives in a `Component::HasPlaceholder` mixin beside the rest of
the `Has*` family.

**It is the odd one in that family, and the entry should say so.** Every existing
`Has*` shares real behavior — `HasCaption` *stores* the caption for all its
includers, which own only the rendering. This one can't: the leaf (`TextField`)
stores and paints, while each composer must **delegate** to `content`, because a
copy in the composer plus a copy in the inner field is two sources of truth for
one fact (the desync `D_tree_api` forbids for slots, in miniature). So every
composer overrides both accessors, and what the mixin actually buys is: the
contract in one place, a shared `inspect_details`, storage for the single leaf,
and `is_a?(HasPlaceholder)` as a lookup/iteration seam — which is the same
justification `HasCaption` gives for being a mixin at all.

Note also that it stores a **`String`**, where `HasCaption` parses into a
`StyledString`. Deliberate, per the ruling above; the rdoc should say why, since
a reader comparing the two mixins will notice the asymmetry.

Two questions the seam *creates*, to be answered in the graduated entry rather
than re-derived by the next reader:

- **`Select` does not include it**, and someone will ask why the moment the seam
  exists. `D_select` already ruled it: a blank face plus `▾` is self-evidently
  "nothing picked", so an enum field with no value needs no format hint. Record
  the exclusion.
- **`DateField`'s placeholder is *derived*, not set** — it comes from the format
  the field writes back. But the mixin promises a settable one. Proposed:
  **derived is the default, an app-set placeholder wins, and `nil` restores the
  derived one.** Least surprising, and it keeps the seam honest instead of
  shipping one includer whose setter silently does nothing.

## Squaring it with two existing decisions

Both will be cited at review, so answer them in the entry that graduates:

- **`D_select` says an optional enum field gets no placeholder string.** Not a
  contradiction, a different case: a blank `Select` face plus `▾` is
  self-evidently "nothing picked", whereas a blank text field cannot tell you
  what shape it wants. The Select ruling is about a *value* that is absent; this
  is about an *input format* that is unguessable.
- **`D_caption_ownership` says a field paints no caption — its container does.**
  Also not a contradiction, and the boundary is exactly the cells: a caption sits
  outside the field's rect, in cells the field neither owns nor invalidates,
  which is the whole reason it belongs to the container. A placeholder is inside
  the field's own rect, on cells the field already paints and already
  invalidates. That test — *whose cells are these?* — is the durable phrasing of
  both rules and belongs in the graduated entry.

  Sharper still, and worth recording beside it: **a caption is unconditional and
  describes the *field*; a placeholder is conditional on emptiness and stands in
  for the *value*.** It occupies the value's own cells, which is what makes it
  value-shaped chrome rather than field-shaped chrome. That framing also answers
  a question this note didn't think to ask — an app must not use a placeholder
  *as* a caption to save a row in a tight form, because the hint disappears the
  instant the user types.

## The ink — barely visible, and therefore *not* `hint_color`

**The design intent, settled first:** a placeholder is a hint the user is welcome
to miss. If they don't notice it, nothing is lost — the field still works and the
value is still theirs to type. So it is painted *barely visible*: readable when
you look at it, invisible when you don't. Everything below is calibration against
that target, not against legibility.

That kills the original plan. `hint_color` is **not** a subdued-secondary-text
token, whatever this note said when it was filed: it is `LIGHT_SKY_BLUE3` (109)
on dark and `TURQUOISE4` on light — a saturated accent, and both of today's
consumers use it to *pull* the eye (the shortcut caption in `"q quit"`;
`PickerWindow`'s option captions). A placeholder in it makes an empty field
*louder* than a filled one, which is the affordance backwards.

**The plan: a gray token first, `dim` held in reserve.**

- **A `placeholder_color` gray token** — v1. It fits how Tuile already does
  color, and the "`ThemeDef` migration for every app" cost this note feared is
  avoidable: give the new kwarg a default in `Theme#initialize` and an app's
  custom theme keeps constructing untouched (a custom *light* theme then wants to
  pass it, since one fixed default can't be right on both sides).
- **A `dim` (SGR 2) attribute on `StyledString::Style`** — the fallback.
  Conceptually the nicer one: dim is *relative* to whatever foreground is in
  play, so it inherits the terminal's own fg exactly the way the no-global-fg
  rule wants, needs no token at all, and does not quantize. But it changes the
  most-specced frozen value type (parse, `to_ansi`, the diff, the sig), which
  deserves its own argument rather than riding in on a placeholder. **Its trigger
  condition is precise** — see the ansi16 finding below: reach for it if and only
  if subtlety on ansi16 terminals turns out to matter.

**The hard part is not the gray, it is that the background varies.** One ink has
to survive five: `input_bg_color`, `active_bg_color`, both error wells, and
terminal-default under `BG_INHERIT`. Since the show condition is `text.empty?`
with no focus term, the *primary* case is a **focused empty field** — so
calibrate against `active_bg_color` (GREY37 dark / GREY82 light), roughly a step
or two up from the well rather than a step down from the foreground. It then
reads slightly stronger on the resting well, which is harmless.

### The ansi16 split decides the shade, and it is decidable now

Measured (`Color#quantize(:ansi16)`), not guessed:

| shade | → ansi16 |
|---|---|
| `GREY27`, `GREY37` — the *dark* wells | `bright_black` |
| `GREY42` … `GREY62` | `bright_black` |
| `GREY70` … `GREY85` — incl. the *light* wells | `white` |

So on an ansi16 terminal there is **no middle ground, in either theme**: every
gray in the subtle range collapses onto its own well and the placeholder becomes
*literally invisible*, while the first shade that separates is already at full
text brightness. That binary is not tunable — it is what `quantize` does.

**Ruling that follows: pick the shade on the loud side of the split** — dark
`GREY70`-ish, light `GREY62`-ish, tunable within those halves. At truecolor and
palette256 the token is used exactly and reads as the intended soft gray; on
ansi16 it degrades to plain-text brightness rather than vanishing. That is the
right way round for a hint the user is *allowed* to miss: the failure mode must
be "less subtle than intended", never "silently absent".

**So the acceptance test is not an eyeball.** The shade must (1) separate from
all four wells at truecolor and palette256, (2) stay visibly weaker than typed
text there, and (3) land on `white`/`bright_black` *away from* its theme's wells
under `quantize(:ansi16)`. Only if (1)–(3) can't be met together does `dim` get
its own argument.

While someone is in `theme.rb`: `hint_color`'s rdoc still says "status-bar hints"
and `Theme#hint` still says "the framework's own call sites rebuild on every
status-bar refresh". Both predate the 0.13.0 status-bar deletion and want
widening to "subdued *accent* text" — which, now that the distinction is the
whole point of this section, is what it has always actually been.

## Settled 2026-09-04

- **It ellipsizes** — `StyledString#ellipsize(rect.width)`, not a bare clip. A
  cut-in-the-middle `dd.mm.yyy` reads as a *complete* format that happens to be
  wrong, where `dd.mm.y…` reads as truncated, and for the motivating case that
  difference is the whole point. Free, too: `ellipsize` already defaults to the
  one-column `…`, which is East-Asian Ambiguous and *already* in Tuile's
  Ambiguous inventory (`Checkbox`, `ComboBox`), so this adds no glyph and reopens
  no `D_ambiguous_width` ruling.
- **An invalid field still shows it.** A required field left empty is the
  commonest invalid state and exactly when a hint about what belongs there is
  most useful — the red well says *something is wrong*, the placeholder says
  *what goes here*, and they are complementary. This is also the background the
  shade is most likely to lose against, so it is a case to check, not merely to
  rule.
- **`TextArea` waits.** Not never — just not until something actually wants one,
  at which point the accessor moves to `AbstractStringField` with **both** paints
  written. A multi-line free-text box rarely has an unguessable *format*, so it
  is not a near-term second caller. Do not pre-build the base.

## Open when picked up

- The exact shade, within the halves the ansi16 split fixes (dark `GREY70`-ish,
  light `GREY62`-ish) — and whether it survives the three-part acceptance test
  above against all four wells.
- Whether `Theme#placeholder_color` ships with a kwarg default (non-breaking for
  apps with custom themes, but one fixed default is wrong on one of the two
  sides) or as a required token with a `ThemeDef` migration note.
- `DateField`'s derived-vs-set precedence — proposed above, not yet ruled.

## Related

`ideas/date-field.md` (the caller that wants it, and the format→placeholder
question),
`D_select` and `D_caption_ownership` (the two precedents above),
`D_input_filters` (why `insert_text` is the buffer seam — a placeholder
deliberately never reaches it),
`D_bg_surface` (`draw_text` as the background choke point),
`D_theme_ref` / the theme rules (paint-time resolution, and why the string stays
unstyled),
`ideas/form-layout.md` (a form layout painting captions is the other half of the
"whose cells are these" boundary).
