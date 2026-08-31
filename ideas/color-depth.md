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
  containing `256color` → `:ansi16` floor. An **invalid override value
  raises** `ArgumentError` (a `TUILE_`-prefixed var is always set
  deliberately; a silently ignored typo means debugging colors forever, and
  the failure lands at startup, the cheapest time). Env-only — **no terminfo**: tuile
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
  about the only consumer; not worth more than that. An RGB color under
  `:ansi16` quantizes **direct** to the nearest of the 16, never two-step via
  the 256 palette — two-step compounds rounding error. Results are
  Symbol-form (`30..37`/`90..97`), respecting the user's terminal scheme.
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
cell emit nothing. The `:truecolor` common case short-circuits to a no-op.

**No memo cache — `quantize` is allocation-free instead.** A `Color → Color`
memo was the first sketch and is **rejected**: its key space is the input
(16.7M RGB triples), and the parsed-ANSI case that justified automatic
downgrade is exactly the adversarial input — a gradient-emitting tool piped
through `LogTextView` grows the cache without bound. (`Buffer::WIDTH_CACHE`
is unbounded too, but distinct graphemes in real text are bounded by fonts
and languages, and each avoided gem call costs ~20× — neither holds here.)
The fix exploits the *output* space being tiny: RGB→256 lands on one of 240
cells, →16 on one of 16 symbols, so an internal frozen 256-entry table of
palette `Color`s (built once at load; the 16 side reuses the `COLOR_SYMBOLS`
constants) makes quantize pure arithmetic (~20 integer ops) plus an array
index returning a shared frozen instance. Zero allocation, O(1) memory.

**Measured (2026-08-31, ruby 3.3.8, `benchmark/quantize.rb`, 1M calls/row)** —
a bounded LRU was also proposed and is **rejected on the numbers**:

```
typical (8 colors):            gradient (100k distinct):
  compute   363 ns/call          compute   359 ns/call
  memo      158 ns/call          memo      217 ns/call  (100k entries)
  lru256    183 ns/call          lru256    648 ns/call  ← 1.8x slower
```

The LRU's best case (small palette, all hits) saves ~180 ns/call — invisible
at real call rates — while on the adversarial gradient (the input a bounded
cache exists to defend against) every miss pays lookup + compute + eviction
and lands 1.8× slower than computing outright. The cache only wins the
workload that needed no help. So: no *keyed* cache.

**Corrected during implementation — one memo is needed after all.**
`quantized_style` runs per dirty **cell**, not per style transition (`sgr_to`
is the per-transition part; the sketch above conflated them). So a
full-screen repaint of RGB-styled content paid the arithmetic 8000 times for
one span: **51 ms vs 15 ms** at `:truecolor`, a 3.4× regression on precisely
the app this feature is for. Fixed with a *one-slot* memo — remember the last
`(style → quantized)` answer, compare by identity, sound because `Style` is
frozen — which restores parity (10.7 vs 9.9 ms) with no key space and no
eviction. Plus two micro-optimizations in `nearest_palette` (destructure
rather than splat; `x * x` rather than `x**2`), together ~2×.

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

**Rejected alternative: raise at render on an unrepresentable color** (apps
supply only representable colors, tuile auto-converting at theme definition,
keeping "expensive" computation out of the render cycle). The fail-fast
instinct matches the house "raise at registration, not gate at runtime"
pattern — but that pattern works because it raises *at the write site,
deterministically, on the developer's machine*. Raise-at-render inverts both:
it fires at the read site (flush, far from the assignment that installed the
color) and only on the *end user's* terminal — the dev's truecolor terminal
and FakeScreen's pinned `:truecolor` never see it, so it ships and crashes on
tmux: breaks-at-a-distance and silent-under-test by design. It converts
"coarser shade" (which the terminal/multiplexer already approximates on its
own) into "app dies mid-repaint"; no peer framework raises. Auto-convert at
theme definition can't run — `ThemeDef.default` is built at load, before any
`Screen`/depth exists — would bake depth into stored state (the
cache-in-an-ivar smell), and covers only the *declared* source: the *parsed*
source (LogTextView ingesting truecolor SGR) has no conversion site and
would crash the moment such a line scrolls into view. And the expense premise
fails: quantization is ~20 integer ops per style transition, allocation-free
— and *checking* representability to decide whether to raise costs the same
case analysis as just quantizing.

Wrinkle: a PTY-based example spec inherits the runner's env, so `COLORTERM`
differs between a dev machine and CI — an example script emitting RGB
produces different wire bytes per environment. Only bites a spec asserting
frame *bytes*; ours assert glyphs. Note it in the spec-side docs, or have PTY
specs export `TUILE_COLOR_DEPTH=truecolor`.

## Spec list (agreed 2026-08-31; implementation held off)

Patterns to mirror: `TerminalBackground.detect` takes `env:` injected (specs
pass plain hashes, no ENV stubbing); `FakeScreen` pins via a private-method
override (`detect_background`); `buffer_spec` already has a `#flush` block,
and `Buffer#mark_all_dirty` exists.

**`spec/tuile/color_depth_spec.rb`** (new) — `.detect(env:)`, one example per
rung: override wins over a contradicting env (override `ansi16` +
`COLORTERM=truecolor` → `:ansi16`), one per legal value; invalid override
raises `ArgumentError`; `COLORTERM=truecolor` and `=24bit` → `:truecolor`;
`TERM=xterm-direct` → `:truecolor`; `TERM=xterm-256color`/`tmux-256color` →
`:palette256`, plus the precedence case `COLORTERM=truecolor` **with**
`TERM=tmux-256color` → `:truecolor` (the tmux-RGB-passthrough escape);
`TERM=xterm`/`linux`/empty env → `:ansi16`.

**`color_spec.rb` — `#quantize`:**
- Identity contract, asserting `equal?` not `==`: Symbol at all three depths;
  palette Integer at `:truecolor`/`:palette256`; RGB at `:truecolor`.
- RGB→256: exact cube cell `rgb(95,135,175)` → `palette(67)`; exact ramp cell
  `rgb(88,88,88)` → `palette(240)`; ramp-beats-cube `rgb(100,100,100)` →
  `palette(241)` (grey 98 at distance 12 vs cube 95 at 75); cube-beats-ramp
  `rgb(255,0,0)` → `palette(196)`; corners `rgb(0,0,0)` → `palette(16)` and
  `rgb(255,255,255)` → `palette(231)` (exact cube cells; the ramp never
  reaches 0 or 255).
- The virtui-tint spec: quantize a real stepped-toward-darker tint of a dark
  bg (`rgb(30,30,34)` territory) and pin the cell — the agreed "revisit
  Euclidean only if this looks wrong on screen" guard.
- →16 under `:ansi16`: `palette(196)` → `Color::BRIGHT_RED`, `palette(16)` →
  `Color::BLACK`; one RGB→16 case pinning the direct (not two-step) path.
- Shared-instance guard: two RGBs on the same cell return the *same*
  instance — `rgb(95,135,175).quantize(:palette256)
  .equal?(rgb(96,135,175).quantize(:palette256))` — pinning the
  allocation-free table against a later `Color.new`-per-call "simplification".
- Edges: invalid depth symbol raises `ArgumentError`; result form matches
  depth (Integer value for 256, Symbol for 16).

**`screen_spec.rb`:** `Screen.fake.color_depth == :truecolor` (the pin, via a
private `detect_color_depth` override mirroring `detect_background`);
`refute respond_to?(:color_depth=)` pinning no-setter; wiring — the screen's
buffer carries the screen's depth (ctor param; the buffer survives resize via
`Buffer#resize`).

**`buffer_spec.rb` — `#flush`**, buffer driven directly with a `color_depth`
defaulting `:truecolor`:
- `:truecolor`: RGB cell flushes `38;2;R;G;B` verbatim (short-circuit guard).
- `:palette256`: RGB fg flushes `38;5;N` with the quantized N; bg `48;5;N`;
  other attributes (bold …) survive alongside.
- Quantize-before-diff: flush `rgb(100,100,100)`, rewrite the cell as
  `rgb(101,101,101)` (style change dirties it), flush again → output contains
  **no color SGR** (both quantize to 241, `sgr_to` between quantized styles
  is empty).
- `:ansi16`: RGB flushes as a base/bright code (`31`/`91` family), never
  `38;5`/`38;2`.
- `region_ansi` returns logical truecolor bytes regardless of depth — pins
  "assertions stay logical, only the wire degrades".

**Untouched on purpose:** `styled_string_spec`'s `parse(to_ansi(x)) == x`
round-trip already pins depth-unawareness of the value types; no PTY/example
changes — no example emits RGB today (the `TUILE_COLOR_DEPTH=truecolor`
export for PTY specs only becomes necessary when one does).

## Registration debt on graduation

rdoc on `ColorDepth` + `Color#quantize` + `Screen#color_depth`; DECISIONS.md
`D_color_depth` (the flush-vs-value-type placement argument lives there);
CHANGELOG `Add` lines; book ch6 paragraph; AGENTS.md layout-list line;
mirrored specs (`color_depth_spec`, quantizer cases in `color_spec`, flush
behavior in `buffer_spec` if automatic); `rake sig`. No README Components row
— nothing here is a component.
