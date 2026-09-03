# Retune the error well colors — the focused one collides with the cursor

**Status:** filed 2026-09-03 from testing the shipped feature. One concrete
problem, one open trade. The *design* is settled and lives in `D_has_validation`;
this note is only about which four colors the two themes name.

## What shipped

| | resting | focused |
|---|---|---|
| `DARK` | `LIGHT_PINK4` (95, `#875f5f`) | `INDIAN_RED` (131, `#af5f5f`) |
| `LIGHT` | `MISTY_ROSE3` (181, `#d7afaf`) | `LIGHT_PINK3` (174, `#d78787`) |

## The problem

**`DARK`'s focused error well (131, `#af5f5f`) is nearly the same color as the
terminal cursor**, so a focused invalid field and the caret sitting in it blur
together. Reported from real use, not from the arithmetic.

Constraints on any replacement — the first three are what the original
measurement checked, and they must keep holding (`D_has_validation`, and the
script below re-runs them):

- **A** resting error well ≠ `input_bg_color`
- **B** focused error well ≠ `active_bg_color`
- **C** focused error well ≠ resting error well — *after* `quantize(:palette256)`,
  not just at truecolor. This is the one that kills most candidates, and losing
  it means a focused invalid `Select` shows no focus at all (it paints no caret).
- **D (new)** neither well should sit near a typical cursor color.

D is the awkward one because Tuile does not know the cursor color: it is the
terminal's, not the theme's, and OSC 12 is the query that would report it —
`Screen#background_color` and `D_background_rgb` are the precedent if it ever
seems worth probing. Almost certainly not worth it for this; picking a well that
is not in the usual cursor neighbourhood is cheaper than a round trip, and
`D_background_rgb`'s own reasoning (a theme picks colors to sit *against* the
terminal) argues for choosing rather than querying.

## Directions to try

- **Move the pair darker and less saturated on `DARK`**, keeping the split: the
  collision is with a *bright* mid-red, so 95 → something in the 52/88 direction
  for the resting well and 95 or 131 for the focused one. Watch C: the earlier
  measurement found `52 → 95` fails B at `ansi16` but holds at 256.
- **Split on lightness rather than saturation** — a darker resting well and the
  current 95 focused, so the focused state reads as *lighter* the way
  `GREY27 → GREY37` does. That is the relation the valid pair already uses, and
  matching it would make the invalid pair feel like the same widget.
- **Reconsider the saturated pair** (`DARK_RED` 52 / palette 88) — it was the
  one candidate that keeps the signal alive on `ansi16` (conditions A and B, not
  C), and it is further from a bright cursor. Cost is the muted look; that trade
  is recorded in `D_has_validation` and is still live.

`LIGHT` was not reported as a problem. Check it anyway if the pair moves, since
the two themes should stay recognizably the same design.

## Re-running the check

```ruby
$LOAD_PATH.unshift "lib"; require "tuile"; include Tuile
def check(label, wells, pair)
  n_well, a_well = wells
  en, ea = pair
  row = %i[truecolor palette256 ansi16].map do |d|
    nw = n_well.quantize(d); aw = a_well.quantize(d)
    n = en.quantize(d); a = ea.quantize(d)
    "#{d}: A=#{n != nw} B=#{a != aw} C=#{a != n}"
  end
  puts "#{label}  #{row.join('  ')}"
end
check("DARK  95/131", [Color::GREY27, Color::GREY37], [Color.palette(95), Color.palette(131)])
check("LIGHT 181/174", [Color::GREY85, Color::GREY82], [Color.palette(181), Color.palette(174)])
```

Changing the tokens is a one-line edit each in `Theme::DARK` / `Theme::LIGHT`
plus the palette indices asserted in `has_validation_spec` and
`sampler_spec` — grep `48;5;`.

## Related

`D_has_validation` (the design, the three conditions, and why the pair is two
opaque tokens rather than a blend), `D_background_rgb` (the OSC-probe precedent,
if D ever needs querying rather than choosing), `D_color_depth` (why there is no
depth-conditional answer).
