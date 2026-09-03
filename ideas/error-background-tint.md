# An invalid field paints a red *well*, not red text

**Status:** brainstormed 2026-09-03, **nothing implemented.** Converged on a
proposal (*The proposal*); the blend/alpha family it started from is measured
and rejected (*Rejected: mixing*), kept because the measurements are the
evidence and are expensive to re-derive. Reopens the "the ink is a foreground"
ruling in `D_has_validation`, which is still `[Unreleased]` — so changing course
costs no migration, and that window closes when 0.15.0 ships.

All numbers are measured against the real `Color#quantize` and the real
`Theme::DARK` / `LIGHT` tokens; reproduction script at the end.

## Why the foreground channel is the wrong one

Two holes, and the first is admitted in `D_has_validation` itself:

1. **An empty invalid field has no glyphs to tint** — which is the
   required-field case, i.e. the single most common validation failure there
   is. A signal that fails on the commonest instance of the thing it signals is
   not a signal.
2. **Undocumented, and worse: `under_fg` is fill-unset**
   (`styled_string.rb:655` skips any span that already has a `fg`). So a
   `RadioGroup` row with a styled label, a `List` with per-item colors, an
   app-colored `TextView` — none of them turn red. The fg channel needs glyphs
   *and* needs them unstyled.

A background needs neither, and arrives at machinery that already exists:
`clear_background` defaults to `bg = effective_bg_color`, so an empty field's
well is painted with no new paint code.

## The proposal

**Two opaque `Theme` tokens, applied as-is. No mixing, no alpha, no
background-derived arithmetic anywhere.**

The reframe that makes this obviously right: *why does a `TextField` or a
`Select` have a well at all?* To show the component's boundary. A red well shows
the boundary **and** the verdict — nothing is lost by replacing one with the
other, and an app can already see there are multiple invalid fields because they
are all red. The focused one is darker, which is the same job
`active_bg_color` does for the valid pair.

So `Theme` gains the invalid variant of a pair it already has:

```
input_bg_color  / active_bg_color         valid
error_bg_color  / error_active_bg_color   invalid
```

`Theme` validates every member `is_a?(Color)`, so two more `Color` members fit
the type as it stands.

**Where the hook goes: above `@bg_color`, not inside `default_bg_color`.**
A new protected `Component#error_bg_color` (nil by default), overridden by
`HasValidation` to `active? ? theme.error_active_bg_color : theme.error_bg_color`:

```
effective_bg_color = resolve(error_bg_color) || resolve(@bg_color) || resolve(default_bg_color) || parent.effective
```

Two reasons it must sit above `@bg_color` rather than in `default_bg_color`:

- The chain is `@bg_color || default_bg_color`, so an app that sets
  `field.bg_color = my_blue` would **silently disable validation ink on that
  field** — the same class of bug as issue #11. An app wanting different error
  colors changes the *theme* tokens, the sanctioned channel; it should not be
  able to switch the signal off by tinting a panel.
- `default_bg_color` is overridden by **six** widgets
  (`abstract_string_field`, `combo_box`, `select`, and the three numeric
  fields), so the in-`default_bg_color` version needs `return super if
  error_message` copied into all six — and a seventh widget added later that
  forgets the line silently shows no error. One level up costs zero per-widget
  lines, recovering the one genuine virtue the fg version had.

`ambient_bg_color` stays untouched: outside its extent the widget is not there,
so the dead tail must not go red (`clear_outside_extent`'s existing rule).

Branch on `active?` and return one `Color` — never a fresh `Hash` — for
`default_bg_color`'s stated reason (an allocation on every row of a `TextArea`
repaint).

### What composition does for free

- **Composed field** (`IntegerField` etc.): the composer includes `HasValidation`
  and answers `error_bg_color`; its inner face is already marked `BG_INHERIT` at
  construction, so it inherits the red. No forwarding.
- **Group** (`RadioGroup`, `CheckboxGroup`): the inner `List` declares no
  background, so the chain walks up to the group. No forwarding.
- **`Checkbox`**: has *no* `default_bg_color`, so today it has no well at all —
  but an invalid one now paints red behind `[ ] I accept the terms`. The
  empty-field case solved for the one widget that had nothing to tint.

### Measured — the token pairs

Three conditions have to hold (`n`/`a` = the invalid normal/active tokens):

- **A** `n ≠ input_bg` — invalid reads while unfocused
- **B** `a ≠ active_bg` — invalid reads while focused
- **C** `a ≠ n` — focus still reads while invalid

| pair | truecolor | palette256 | ansi16 |
|---|---|---|---|
| DARK 95/131 `#875f5f` `#af5f5f` | A B C | A B C | — |
| DARK 52/88 `#5f0000` `#870000` | A B C | A B C | **A B** |
| LIGHT 181/174 `#d7afaf` `#d78787` | A B C | A B C | — |
| LIGHT 224/217 `#ffd7d7` `#ffafaf` | A B C | A B C | A, C |

**Every pair passes all three at truecolor and palette256** — the constraint
that made the blend hard simply evaporates, because you *choose* two colors
instead of hoping a contraction leaves a gap between them.

Two findings worth keeping:

- **The blend's own best outputs were 95, 131 (dark) and 174, 181 (light) —
  exactly these palette cells.** The opaque pair picks the destination directly
  and discards the machinery that was struggling to land on it.
- **A saturated pair partially revives `ansi16`**, which no blend could:
  52/88 keeps A and B (red vs. grey), losing only C — and focus is already dead
  there (see below). That is a real trade against "slight": muted 95/131 is the
  tasteful well, and gives `ansi16` nothing.

Leaning muted (DARK 95/131, LIGHT 181/174) — same hue family, and `181/174` sits
at the wells' own luminance where `224/217` is *lighter* than `#dadada`, which
would make an invalid field read as less recessed than a valid one.

## Rejected: mixing the well toward `error_color`

The first design: resolve `effective_bg_color` normally, then blend it toward
`Theme#error_color`. Attractive because it composes with an app's custom panel
tint, and because modelling error as a *transform over* the resolved background
(rather than a fourth value in `BG_STATES`) dissolves the 2×2 precedence
objection `D_has_validation` raised. That reframe survives and is what the
proposal above inherits — the *transform* is what died.

**Why it died: a lerp is a contraction.**
`|tint(active) − tint(normal)| = (1−w)·|active − normal|` — the tint squeezes
out the very focus shade it composes with. At truecolor that never bites (A∧B∧C
hold at every weight). Under `palette256`:

| w | DARK n→a | | LIGHT n→a | |
|---|---|---|---|---|
| 0.15 | 239 → 95 | OK | 181 → 181 | **C fails** |
| 0.20 | 240 → 95 | OK | 181 → 181 | **C fails** |
| 0.25 | 240 → 95 | OK | 181 → 181 | **C fails** |
| 0.30 | 95 → 95 | **C fails** | 174 → 174 | **C fails** |
| 0.40 | 95 → 131 | OK | 174 → 138 | OK |
| 0.50 | 131 → 131 | **C fails** | 167 → 131 | OK |

`w = 0.40` is the *only* single weight satisfying A∧B∧C in both schemes — and
0.40 is `#8f4f4f` / `#c98383`, not "slight". Below ~0.20 on dark the tint
quantizes back onto the **grey ramp** (239, 240), so it reads as "slightly
lighter grey", not red — A passes on a technicality.

**The elegant repair is worse, don't re-derive it.** Since the failure is
contraction, add chroma without touching luminance:
`base[i] + w·(err[i] − luma(err))`, which preserves the base's delta *exactly*
(dark at w=0.30: `n=(102,54,54)`, `a=(129,81,81)` — delta 27 in every channel,
the base's 95−68). Measured at `palette256`:

| w | DARK lerp | DARK offset | LIGHT lerp | LIGHT offset |
|---|---|---|---|---|
| 0.15 | OK 239→95 | fail 238→59 | fail 181→181 | fail 224→252 |
| 0.20 | OK 240→95 | fail 238→95 | fail 181→181 | fail 224→252 |
| 0.25 | OK 240→95 | fail 238→95 | fail 181→181 | **OK 224→217** |
| 0.30 | fail 95→95 | fail 238→95 | fail 174→174 | **OK 224→217** |
| 0.40 | OK 95→131 | fail 238→95 | OK 174→138 | **OK 224→217** |

It is strictly nicer at truecolor and better on LIGHT at 256, but **fails A on
DARK at every weight**: the dark grey ramp is dense (~10 apart), so a
chroma-only shift off a dark grey snaps back onto the ramp. The elegant
primitive is the worse one on the default theme.

The escape hatch considered last was a per-scheme *weight* as a `Theme` token
(DARK ~0.25, LIGHT 0.40). It works, but `Theme` validates every member
`is_a?(Color)`, so it would have meant loosening that check to admit a Float —
and two opaque `Color` members do the same job inside the type as it stands.

Also rejected along the way, with the reasons that killed each:

- **An opaque red that *replaces* the well with one colour.** Reproduces a bug
  `D_bg_surface` already named when it rejected putting the focus shade inside
  the hook: *"`select.bg_color = X` silently removes the only focus indicator a
  `Select` has — it paints no caret."* The two-token pair is what fixes this,
  and is the whole reason there are two.
- **Blending against `Screen#background_color`.** Unnecessary: blending against
  `effective_bg_color` already blends against whatever will be in the cell,
  since a field with its own well *terminates* the chain (the layout's tint is
  covered, not behind it) and a widget without one walks up to the layout's
  colour. `background_color` was only ever the last rung.
- **Real alpha in `Color`.** Buys multi-layer composition; nothing needs more
  than one layer. Settled while brainstorming and worth not re-deriving:
  **alpha can never reach the `Buffer`** — terminal cells are opaque
  (`D_bg_inherit`), a cell holds one final colour, and there is nothing
  underneath to composite against except the previous frame. It would have to be
  flattened during *resolution*, with the final `effective_bg_color` as sole
  compositor. And putting alpha in `Color` makes the value type partial: a
  translucent colour has nothing to hand `sgr_codes`, so it either raises deep
  in `flush` (a bad error site) or becomes a fifth kind in `resolve_bg_color`'s
  `case`. **That decision belongs to `ideas/modal-backdrop.md`**, which has the
  harder version — dimming every cell under a popup is a fan-out over unknown,
  app-authored bases, not one known one.

**`Color#mix` is not needed by this design any more,** but `modal-backdrop.md`
still is on record wanting it (*"`Color` has no darken/blend operation yet,
which a dim factor would need"*). It should be built there, on that note's
requirements, not pre-emptively here. If it ever is, the open question it
inherits is what `mix` does with a *named* colour: `Color`'s rdoc says a
`Symbol` value has no RGB — "the terminal's scheme decides what it looks like" —
while `quantize(:ansi16)` already cheats with xterm's defaults and admits it's
"the one mapping here that can be honestly wrong".

## `ansi16` is already lost, and not by this

`GREY27` and `GREY37` both quantize to `:bright_black`; `GREY85` and `GREY82`
both to `:white`. **Focus is invisible on a 16-color terminal today.** So
condition C failing there costs nothing that isn't already gone, and chasing it
would mean a depth-conditional *strategy*, which `D_color_depth` puts out of
bounds (the wire is the only place that knows the depth). Choosing a saturated
token pair is the one lever that helps, and it helps A and B rather than C.

## Decided in review (2026-09-03)

**The fg ink goes.** One channel, not two — red text on a red well is muddy.
Delete `Component#content_fg_color`, `Component#effective_content_fg_color` and
`StyledString#under_fg` (no other consumer), and drop the `under_fg` call from
`draw_text` / `draw_char`. `Theme#error_color` survives with the cleaner job:
the colour a `FormLayout` paints the *message* in.

**An invalid section needs no new rule — the existing chain already answers
it.** With the hook above `@bg_color`, a `TextField` inside an invalid section
resolves its *own* `error_bg_color` (nil, it is not itself invalid), then its
own well, and terminates: it keeps its grey well, and the section's red shows in
the cells the section actually owns — its padding and the gaps between fields.
A `Checkbox` in the same section declares no background, so it walks up and
lands on the red. That is not an inconsistency to fix; it is the same rule an
app-tinted panel already follows, and it is how a form section renders in every
GUI: the group is framed in red, the fields inside stay fields until one of them
is itself the problem. So **`error_bg_color` does *not* get an inheriting walk
of its own** — no `effective_error_bg_color`, nothing mirroring what
`content_fg_color` had.

**Mark red on `bad_input?` too.** The predicate is
`bad_input? || !error_message.nil?` — there is deliberately no `invalid?`
(`D_has_validation`), and this must not grow one, since it would be a third
predicate beside the two it ORs. Accepted with `D_bad_input`'s continuity
problem understood rather than solved, so the concrete symptom is on the record:

- `IntegerField`, typing `-42`: red at `-`, gone at `-4`. One keystroke, because
  `TYPEABLE` is `/\A-?\d*\z/` so `"-"` is the *only* reachable bad input.
- `FloatField`, typing `1.5`: red at `1.`. Typing `1e-5`: red at `1e` and
  `1e-`. Two or three keystrokes, since `TYPEABLE` admits partial exponents.

If that flicker proves annoying in use, the fix is the settling rule
`ideas/bad-input.md` §3 already owes (settle on blur, or after a Ticker delay) —
applied to the *ink*, not to `bad_input?` itself, which must stay derived-on-read
for the click-time save gate. Do not "fix" it by narrowing `TYPEABLE`: a
prefix-closed grammar is what makes the input filter work at all
(`D_input_filters`).

**No delegation is needed for a composed field.** `IntegerField` and friends
already set `field.bg_color = BG_INHERIT` at construction
(`integer_field.rb:76`, `float_field.rb:87`, and the `ComboBox` /
`BigDecimalField` equivalents), so the inner face declares no background of its
own and takes the composer's — including the composer's red. The composer holds
`error_message` because it holds the `HasValue` seam; the inner `TextField`'s
own `error_message` stays nil and unused. Nothing forwards anything.

## Still open

1. **Which pair.** Leaning **muted**: DARK `LIGHT_PINK4` (95, `#875f5f`) /
   `INDIAN_RED` (131, `#af5f5f`), LIGHT `MISTY_ROSE3` (181, `#d7afaf`) /
   `LIGHT_PINK3` (174, `#d78787`). All four already have `Color::` constants,
   where the saturated alternative's 88 is unnamed and would need
   `Color.palette(88)`. Wants eyes on a real terminal once implemented — the
   trade is a tasteful well versus one that survives `ansi16`, and no further
   arithmetic will settle it.

## Reproduction

```ruby
$LOAD_PATH.unshift "lib"; require "tuile"; include Tuile
def show(label, wells, pairs)
  n_well, a_well = wells
  pairs.each do |en, ea|
    row = %i[truecolor palette256 ansi16].map do |d|
      nw = n_well.quantize(d); aw = a_well.quantize(d)
      n = en.quantize(d); a = ea.quantize(d)
      "#{d}: A=#{n != nw} B=#{a != aw} C=#{a != n}"
    end
    puts "#{label} #{en.value}/#{ea.value}  #{row.join("  ")}"
  end
end
show("DARK ", [Color::GREY27, Color::GREY37],
     [[Color.palette(95), Color.palette(131)], [Color.palette(52), Color.palette(88)]])
show("LIGHT", [Color::GREY85, Color::GREY82],
     [[Color.palette(181), Color.palette(174)], [Color.palette(224), Color.palette(217)]])
```

## Related

`D_has_validation` (the entry this reopens — its *Known gap* and its foreground
ruling), `D_bg_surface` (the resolution chain, `BG_STATES` closed, and the
`Select`-has-no-caret finding), `D_bg_inherit` (terminal cells are opaque; no
global bg token), `D_background_rgb` (`Screen#background_color` — not needed
after all, and why), `D_color_depth` (quantization at the wire only),
`ideas/modal-backdrop.md` (owns `Color#mix` and the alpha type question),
`ideas/hover.md` step 3 (a possible further consumer, deliberately undecided),
`ideas/bad-input.md` §3 (the settling rule an OR with `bad_input?` still owes).
