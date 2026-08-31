# Color depth — detect it, and let a computed RGB degrade to the 256-palette

**Status:** design settled, 2026-08-31; not yet implemented. Upstream ticket:
<https://github.com/mvysny/tuile/issues/8>.

## The problem (from #8, condensed)

`Color#sgr_codes` emits `48;2;R;G;B` for every RGB `Color` unconditionally.
Fine while RGB only came from declaration sites; #7 broke that — an app can
now *read* the terminal background as RGB and *derive* a color from it
(virtui's borderless-panes tint: step the reported bg toward its own pole).
Under a 256-color terminal, or tmux without `terminal-features "*:RGB"`, the
computed `48;2;…` is mangled or silently approximated. Half of #7's loop is
open.

## Settled decisions

- **`Screen#color_depth`** — `:truecolor` / `:palette256` / `:ansi16`.
  Three-valued symbol, not `truecolor?`: `:ansi16` must stay expressible.
- **Detected once at `Screen` construction, then set in stone.** No
  `color_depth=` setter — the ticket doesn't ask for one, misdetection is
  covered by the env override, and a setter drags in a real bug: `Cell#set`
  flips dirty only on a *style* change, but a depth change alters the *bytes*
  an unchanged style emits, so the minimal diff has nothing to notice and the
  setter would need a buffer-wide dirty-all. Deleting the setter deletes the
  wrinkle.
- **Detection ladder** (first hit wins): `TUILE_COLOR_DEPTH` env override →
  `COLORTERM` = `truecolor`/`24bit` → `TERM` containing `-direct` → `TERM`
  containing `256color` → `:ansi16` floor. Env-only — **no terminfo**: tuile
  has no terminfo access (tty-screen does geometry, not capabilities), real
  terminfo means shelling out to `tput`/`infocmp` at startup, and the
  env ladder plus the override covers the real matrix. tmux/ssh misdetect
  *conservatively* (256 on a truecolor terminal), which is the safe direction:
  coarser, never wrong. No stdin round-trip, so unlike #7 there is no
  key-thread timing constraint and no staleness story.
- **A pure module + a `Screen` holder, mirroring #7's split.** New
  `lib/tuile/color_depth.rb`, `Tuile::ColorDepth.detect` — parallel to
  `TerminalBackground.detect`. `FakeScreen` pins `:truecolor` the same way it
  pins `detect_background`, keeping every existing spec byte-identical and
  deterministic off the runner's environment.
- **`Color#quantize(depth)`** — a pure value method, total over all three
  value forms: a Symbol color returns `self` at every depth; a palette
  Integer returns `self` except under `:ansi16` (a 16-color terminal doesn't
  understand `38;5;N` either); RGB quantizes for anything below `:truecolor`.
  No table for the 256 target — two formulas: the 6×6×6 cube at 16..231
  (per-channel nearest of levels 0/95/135/175/215/255, which *is* the
  Euclidean-nearest cube cell since the axes are independent) and the grey
  ramp at 232..255 (`8 + 10n`); return the nearer candidate.
- **Identity-return is the contract, and there is no separate predicate.**
  "Needs translation" is a function of (form, depth) — a bare `from_palette?`
  is ambiguous between the 256 and ansi16 targets, and `full_rgb?` misses the
  palette→16 case — so the filter lives in `quantize`'s own case, and "no
  translation needed" is documented to return **the same instance**
  (`equal?(self)`, not just `==`). A caller wanting the predicate has
  `color.quantize(depth).equal?(color)` for free; a separate
  `needs_quantize?(depth)` would restate the case as a boolean and drift.
  Form-introspection sugar (`named?` / `palette?` / `rgb?`, matching the
  factory names) is deliberately left out until an app asks — `color.value`
  already answers it.
- **Distance metric: plain squared-Euclidean RGB.** Not perceptual. If
  virtui's tint-stepping produces near-greys, the cube-vs-ramp tiebreak is
  where a perceptual weight would show — so one spec quantizes a real
  virtui-style tint, and we revisit only if that spec looks wrong on screen.
- **`:ansi16` is detected honestly and quantized with xterm default RGBs**
  for the 16 base colors — the one lossy-and-possibly-wrong mapping (the base
  16 are terminal-theme-dependent), rdoc carries the caveat. `TERM=linux` is
  about the only consumer; not worth more than that.
- **`Color` and `StyledString` stay depth-unaware.** The downgrade must not
  live in `sgr_codes`/`Style#sgr_to` reading a global: both classes are pure
  frozen value types with zero `Screen` dependency and a
  `parse(to_ansi(x)) == x` round-trip pinned by spec — the same rule that
  keeps `StyledString` theme-unaware. (`#quantize` is fine: depth comes in as
  an argument, purity intact.)

## Settled: automatic at flush, AND public `quantize` — with nothing pre-quantized

**Decided 2026-08-31.** The mental model: **logical layer always truecolor,
wire layer always terminal-native, one conversion at the boundary.** ThemeDef
tokens and computed tints stay truecolor in memory for the app's whole life;
nothing pre-quantizes at a declaration or derivation site — that would be
redundant (flush catches it anyway) and would bake depth into stored state,
the cache-in-an-ivar smell: a stored `Color.palette(237)` has forgotten it was
`#3a3a3a`, so contrast checks and further derivations work from the lossy
copy. Public `Color#quantize` exists so an app can *know* what a color becomes
on the wire (virtui checking its tint still contrasts with the bg after both
round to palette cells) without changing what it stores.

The choke point is `Buffer#flush` — where logical cells become wire bytes
(`style.sgr_to(c.style)`), the same role `draw_text` plays for backgrounds.
Screen hands the buffer its depth; flush maps each style's fg/bg through
`quantize` *before* the `sgr_to` diff, so two RGBs landing on the same palette
cell emit nothing. Memoize `Color → Color` (colors are frozen and hash-equal;
the cache is bounded by distinct colors in use), and the `:truecolor` common
case short-circuits to a no-op.

Why automatic won (record in `D_color_depth`):

- **The deciding argument: not all RGB has a call site to opt in at.** RGB
  enters an app three ways — *declared* (`Color.hex` theme tokens),
  *computed* (virtui's tint), and *parsed*: `StyledString.parse` ingests ANSI
  produced by other programs (a `LogTextView` fed a tool's colored output).
  Parsed colors arrive as data with no declaration site, no app author would
  walk spans to quantize them, and `StyledString` must stay depth-unaware.
  Only the wire choke point catches this case.
- The "keeps `sgr_codes` honest" objection dissolves at this placement:
  quantization happens in `Buffer`, `Color` still emits exactly what it was
  given — and the buffer already doesn't emit what you wrote (minimal diff,
  sync batches). Adapting the logical frame to the physical terminal *is* the
  buffer's job.
- No collision with the house allergy to "automatic": the deleted automatic
  channels (`content_size`, `keyboard_hint`) were semantic queries the
  framework made *of components*. Flush-time quantization consults nobody —
  no new `Component` API, one field on `Buffer`, deletable in one commit.
- Prior art is near-unanimous: Rich (`Color.downgrade` at render), Textual,
  tcell (RGB→palette at the screen layer — exactly this placement), chalk,
  notcurses. The one ecosystem leaving it to apps (crossterm/ratatui) is the
  one whose apps notoriously render wrong on non-truecolor terminals.
- Costs, honestly: `region_ansi` (logical truecolor) won't byte-match a real
  terminal capture on a 256 terminal (rdoc note); misdetection to
  `:palette256` renders coarser silently, but `TUILE_COLOR_DEPTH=truecolor`
  forces the depth and flush becomes a no-op — automatic ships with its own
  off switch, no extra knob needed.

Wrinkle: a PTY-based example spec inherits the runner's env, so `COLORTERM`
differs between a dev machine and CI — an example script emitting RGB
produces different wire bytes per environment. Only bites a spec asserting
frame *bytes*; ours assert glyphs. Note it in the spec-side docs, or have PTY
specs export `TUILE_COLOR_DEPTH=truecolor`.

## Registration debt on graduation

rdoc on `ColorDepth` + `Color#quantize` + `Screen#color_depth`; DECISIONS.md
`D_color_depth` (the flush-vs-value-type placement argument lives there);
CHANGELOG `Add` lines; book ch6 paragraph; AGENTS.md layout-list line;
mirrored specs (`color_depth_spec`, quantizer cases in `color_spec`, flush
behavior in `buffer_spec` if automatic); `rake sig`. No README Components row
— nothing here is a component.
