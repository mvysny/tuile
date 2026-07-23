# Background-fill color (issue #1)

**Status:** brainstorm, not yet implemented. Tracks
<https://github.com/mvysny/tuile/issues/1>.

## The problem

A slash-command / autocomplete popup (cf. `examples/sampler.rb`
`build_slash_demo`) wants a *distinctive background across the whole
list* — content rows **and** the blank filler rows below the matches —
so the overlay reads as a solid tinted panel floating over the input.

Today there's no way to get it. `List#repaint` paints each row via
`paintable_line`; the only `bg:` it applies is the per-row cursor
highlight (`active_bg_color`). Content rows are padded to full width but
drawn on the terminal default background; blank filler rows use the
private `@blank_padded`, unreachable from `lines=`. So setting `bg:` on
the `StyledString`s you pass to `lines=` tints only the matched rows and
leaves the filler below on the default background — a ragged, half-shaded
box. `Window` paints only its border; `TextField`/`TextArea` have
`input_bg_color`; `List` has no equivalent.

## The load-bearing constraint: terminal cells are opaque

There is no transparency in a cell grid. Every cell holds exactly one
`bg`; a child painting a space with `DEFAULT_STYLE` *overwrites* whatever
its parent filled there. That splits components into two camps, and the
design has to serve both:

- **Gap-leavers** (default `repaint` path): the base `repaint` calls
  `clear_background` → `buffer.fill(rect)` for the parts children don't
  cover. A background color slots in here trivially — fill with a bg
  style instead of `DEFAULT_STYLE`. Panels, `Layout`, `Window`'s inner
  area (Window calls `super`, so it inherits this) all get the tint in
  their gaps *for free*.
- **Self-painters** (`List`, and `Window`'s border): they opt *out* of
  the base `repaint` and paint every cell of their rect themselves.
  `clear_background` never runs for them, so a base `fill`-based
  background never reaches them. `List` — the actual target of this
  ticket — must **bake the bg into every row it emits** (content +
  filler), and still compose `active_bg_color` on the cursor row on top.

So the ticket's "List inherits it for free" hope is only half true: List
inherits the *attribute*, but has to *implement the fill itself* because
it self-paints. That's fine — but it's the reason the base setting alone
isn't a complete answer.

## Two shapes

### A. `List#background_color=` (the minimal fix)

A `Color` (default `nil` = today's behavior) on `List`. When set,
`pad_to_row` styles both real lines and `@blank_padded` with that bg;
`paintable_line` composes `active_bg_color` over it on the cursor row via
`with_bg` (already how the highlight is applied). Contained, obviously
correct, solves the slash-popup case. Doesn't generalize.

### B. `Component#background_color` on the base (the general shape)

One attr on `Component` (default `nil`). Semantics: *"fill my `rect` with
this bg."* Consumed in two places to cover both camps under one API:

1. `clear_background` fills with `Style.new(bg:)` when set (gap-leavers,
   Window content gaps, panels — all for free).
2. `List` reads the same inherited attr and bakes it into its rows (it
   self-paints, so it can't ride #1). Its cursor row still composes
   `active_bg_color` on top.

One public knob, one meaning, consistent everywhere. List's extra work is
an implementation detail hidden behind the shared attribute.

**Recommendation: B.** Same effort for the List path (List must bake
either way), and it hands panels/`Window`/`Layout` the capability with no
extra surface. The name and semantics are the general ones the ticket
itself gravitated toward.

### Interaction to document (B)

`children_tile_rect?` makes the base `repaint` skip `clear_background`
when children fully tile the rect — so a fully-tiled container's
`background_color` won't paint. That's correct: it would be 100%
occluded anyway. The bg is a **gap fill** (plus, for self-painters, a
row bake). A container that wants the tint to *show through* its children
must leave gaps or use children with the same bg — cells are opaque, so
there's no "tint behind opaque children." Call this out in the rdoc so
nobody files it as a bug.

## Theme token? (No, keep the mechanism app-owned)

The ticket asks for "ideally a theme token so it tracks light/dark." I'd
resist adding a built-in one. AGENTS.md's theme section is explicit:
non-accent cells deliberately inherit the terminal default; there is *no
global bg/fg token* — that's the whole light-theme strategy. A stock
`panel_bg` token would poke a hole in that stance.

Instead: `background_color=` takes a `Color`. An app that wants it
theme-tracked sources it from a **custom** theme token
(`theme[:panel_bg]`, paired dark/light in its `ThemeDef`) and reassigns
it in `on_theme_changed` — exactly the documented pattern for
theme-derived colors baked into content (`Label#text`, `List#lines`). The
framework supplies the mechanism; the app owns the policy. This keeps the
"no global bg token" invariant intact while fully satisfying the
light/dark-tracking need.

(Consequence: `background_color` is a plain `Color` ivar read at paint
time. A bare `theme=` flip does *not* restyle it — the app rebuilds it in
the hook, same as every other content color. Worth a one-line rdoc note.)

## Sketch (option B)

```ruby
# component.rb
attr_reader :background_color            # Color | nil, default nil

def background_color=(color)
  color = Color.coerce(color) unless color.nil?   # match lenient call sites
  return if @background_color == color
  @background_color = color
  invalidate
end

def clear_background
  return super unless @background_color   # keeps the plain-fill path unchanged

  screen.buffer.fill(rect, StyledString::Style.new(bg: @background_color))
end
# (super here == today's body: screen.buffer.fill(rect), i.e. Buffer::DEFAULT_STYLE
#  == StyledString::Style::DEFAULT. Or just inline the fill with the ternary.)
```

```ruby
# list.rb — self-painter, bakes the inherited attr into every row
def pad_to_row(line)
  # ... existing ellipsize/pad ...
  row = StyledString.plain(" ") + body + StyledString.plain(" " * (fill + 1))
  @background_color ? row.with_bg(@background_color) : row
end
# @blank_padded already goes through pad_to_row via rebuild_padded_lines,
# so filler rows get the tint too — the exact gap the ticket hit.
# paintable_line's cursor-row `with_bg(active_bg_color)` still composes on top.
```

`background_color=` must call `rebuild_padded_lines` on `List` (the bg is
baked at pad time) — or bake it in `paintable_line` instead of
`pad_to_row` to avoid the rebuild. Baking in `paintable_line` is simpler
(no rebuild, no extra state coupling) at the cost of one `with_bg` per
visible row per paint; viewport-bounded, negligible. **Lean
`paintable_line`.**

## Open questions

1. Coerce or strict? Call sites elsewhere use lenient `Color.coerce`;
   themes are strict `Color`-only. `background_color=` is a per-component
   knob set at call sites, not a theme declaration → **lenient coerce**,
   matching `Label`/`List` content APIs.
2. `nil` vs an explicit "transparent" sentinel — `nil` = terminal
   default is the established idiom (`fg: nil`), keep it.
3. Does `Window` want the tint to include the border interior, or only
   the content area? With B it's automatic: the content area (a child /
   gap) tints via `clear_background`; the border stays chrome. Probably
   the right default — revisit if a fully-tinted window (border cells
   included) is ever wanted.

## Next steps

- Confirm B over A, and the no-theme-token stance.
- Implement base attr + `clear_background` change + List `paintable_line`
  bake.
- Specs: List filler rows tinted (`region_ansi` over the blank area);
  cursor row composes `active_bg` over the fill; a gap-leaving Layout/
  Window tints its gaps; `nil` = unchanged from today.
- Wire `examples/sampler.rb`'s slash demo to prove the end-to-end look.
- On completion, graduate per AGENTS.md: reader-half → book (theming or a
  short "backgrounds" note), invariant-half → AGENTS.md (the opaque-cell
  gap-fill-vs-bake rule), retire this file.
```
