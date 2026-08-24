# Horizontal scrolling for the strips (`Tabs`, `MenuBar`)

**Status:** designed 2026-08-24, unimplemented. This is `D-tabs`' deferred v2
("v1 clips the strip; scrolling is v2 … the horizontal scroll window
(`TextField#visible_text`'s pattern) plus `‹ ›` arrows, purely additively"),
extended to {Tuile::Component::MenuBar}, which shipped with the same limitation
and the same skeleton.

## The problem

Both strips paint left to right until the rect runs out and clip the
overflowing segment. Nothing brings the selection into view, so on a starved
strip arrowing into an off-screen tab changes the pane while the visible strip
doesn't move, and a `MenuBar` whose items outrun the terminal has menus that
cannot be reached at all. `D-tabs` shipped that knowingly ("the one rough edge
shipped knowingly") on the bet that a strip has 3–5 tabs; a narrow terminal
breaks the bet without anyone doing anything unusual.

## The design in one number

**`@left_column`** — the strip column painted in the rect's leftmost cell. Name
and semantics lifted from `TextField`'s private `left_column`, so the gem has
one word for a horizontal offset the way `scroll_top_row` is its one word for a
vertical one. Private here too, see the decisions below.

**The invariant:** *the selected tab / highlighted menu item is fully visible,
and `@left_column` is the smallest change from its current value that achieves
it.* One idempotent private `adjust_left_column` is its **sole writer** — the
{Tuile::Component::ProgressBar#sync_ticker} shape (write the condition, sync
from every mutation site), not a nudge at each call site:

```ruby
# `target` is @selected_index (Tabs) / @highlighted_index (MenuBar).
def adjust_left_column
  return @left_column = 0 if rect.empty? || painted_width <= rect.width || target.nil?

  _x, start, width = segments[target]
  if width >= rect.width                        # a caption wider than the strip
    @left_column = start                        # show its head, clip its tail
  else
    @left_column = start if start < @left_column
    @left_column = start + width - rect.width if start + width > @left_column + rect.width
  end
  @left_column = snap_to_glyph_start(@left_column.clamp(0, painted_width - rect.width))
end
```

Three things fall out rather than being special-cased: `@left_column` is `0` in
**every** situation today's code handles (so nothing existing changes — that is
a regression spec, not a footnote); the clamp scrolls back on its own when
captions shrink or the rect widens, so no mutator owes a "scroll back" branch;
and the over-wide caption is an explicit branch rather than two rules fighting
(without it the second rule wins and shows the caption's *tail*, which is the
half that says least).

### Where it is read — three touchpoints, plus one on `MenuBar`

| | today | with the offset |
|---|---|---|
| paint | `strip_row.slice(0, rect.width)` | `strip_row.slice(@left_column, rect.width)` |
| hit test (`tab_at` / `index_at`) | `point.x - rect.left` | `point.x - rect.left + @left_column` |
| `extent` width | `[painted_width, rect.width].min` | `[painted_width - @left_column, rect.width].min` |
| `MenuBar#segment_rect` | `rect.left + start` | `rect.left + start - @left_column` |

Paint and hit test keep reading **one** source (`segments` + the offset), which
is the invariant `D-tabs` already names: "one source, or a click lands on the
wrong tab". A consequence worth a spec: a click on a *partially* visible edge
segment selects it, and the sync then pulls it fully into view. That is a free
affordance, not a wart.

`extent` shrinking with the offset keeps the dead-tail rule honest at the right
end of a fully scrolled strip: those columns select nothing, exactly as the
blank tail does today.

### The call sites — the sync's completeness *is* the feature

| `Tabs` | `MenuBar` |
|---|---|
| `on_width_changed` (new) | `on_width_changed` (new; `rect=` keeps closing the cascade) |
| `apply_selection` | a new private `highlight=(index)` |
| `add_tab` / `remove_tab` | `add_item` |
| `Tab#caption=` | — (items are immutable after `add_item`) |
| `separator=` | — |

`on_width_changed` rather than a `rect=` override: the offset is strip-relative,
so only a width change can invalidate it, and `Component#rect=` already assigns
`@rect` before firing the hook (`component.rb:37`). {Tuile::Component::List}
drops its row cache from the same hook.

`MenuBar` today writes `@highlighted_index` from three places — `move_highlight`,
`handle_mnemonic` and `handle_mouse` — and adding a fourth obligation to each is
exactly the drift the sole-writer rule exists to prevent. Route all three
through one private writer that assigns, adjusts and invalidates.

That ordering also settles the cascade: because `highlight=` syncs *before*
`show_highlighted_menu` runs, the anchor segment is always fully on screen when
a panel opens, so `ListDropdown#anchor_to` needs nothing. `step_menu` reopens
after moving, and `rect=` still closes the cascade outright, so no path scrolls
the strip out from under an open panel — the stale-anchor hazard `D-menu-bar`
closed the cascade for stays closed.

## The trap: `slice` *drops* a straddling wide glyph

`StyledString#slice_text_by_columns` drops a cluster that only partially
overlaps the window ("any other case = partial overlap with a wide glyph —
drop") rather than half-painting it. Right for the buffer, wrong for us: the
returned row comes back one column **short**, so everything after the hole
shifts left by one and paint disagrees with the hit test — silently, only for
CJK/emoji captions, only at some offsets.

{Tuile::Component::TextField} already solved this with `snap_to_glyph_start`
(snap *forward*: the only safe direction). The strips need the same snap over
the assembled strip row. Second copy of ~6 lines, deliberate — see the
duplication decision. Snapping forward can only ever give up one column of the
*previous* segment, never of the one being revealed, because the offset that
needs snapping is the one computed from the revealed segment's right edge.

## Decisions

**Column-exact minimal scroll, not segment-aligned.** The alternative — keep
`@left_column` on a segment boundary, i.e. scroll by whole tabs — buys clean
edges and no snap at all (a segment starts with a padding space, so a boundary
is always a glyph boundary), and costs up to a segment's width of dead space at
the right edge plus a coarser follow. Rejected because a cut caption at the edge
*is* the overflow indicator `D-tabs` deliberately kept ("a visibly cut word says
'there's more' where dropping it leaves clean space reading as 'that's all the
tabs'"), and because a starved strip is precisely where wasting columns hurts.
The snap is the price, and it has a precedent to copy.

**Cues overlay the edge columns; they are not reserved.** Minimal scrolling
usually leaves a cut caption at each edge, but not reliably — when the offset
lands on a boundary the edge is clean and reads as "that's all". So paint `<` at
`rect.left` when `@left_column > 0`, and `>` at `rect.left + rect.width - 1`
when `@left_column + rect.width < painted_width`, *after* the row.

Reserving two columns instead (viewport = `rect.width - 2` while overflowing)
was rejected: it makes the viewport width a function of the scroll state, which
is the `:auto`-scrollbar circularity `D-select` rules out — and it shifts the
whole strip sideways the moment a caption is edited. An overlay keeps the
viewport at `rect.width` unconditionally, needs no monotonicity argument, and
{Tuile::Buffer#put_char} already blanks the partner cell if the cue lands on
half of a wide glyph.

The cue **keeps the style of the cell it covers** —
`row.slice(col, 1).spans.first&.style` — so a cue landing on the selected
segment's last padding column doesn't punch a default-background hole in the
highlight. No new theme token (`D-color-slots`).

**Cues are painted focused or not.** Overflow is a fact about the rect and the
captions, not about focus, and a reader deciding whether to reach for the strip
at all is exactly who needs to know there is more of it. This deliberately
splits from `MenuBar`'s highlight, which *is* focus-gated because it reports a
transient position (`D-menu-bar`), and lands on the same side as `Tabs`' always-
bold selection: both say "here is what the strip contains", which survives focus
moving on.

**ASCII `<` / `>`, and no knob.** `‹ ›` are East-Asian Ambiguous, and the rule
is default to ASCII when the pretty glyph is Ambiguous. Offering the glyph as an
opt-in knob is the *second* half of that rule, but a knob with no caller is a
knob to argue about later: `mask_char=` exists because a password field's glyph
is the whole point, and a cue is not. Re-grow: `cue_glyphs=` if a real caller
appears.

**The cues are chrome, not buttons.** A click on a cue column falls through to
the segment painted under it — which is the partially visible one, so the click
scrolls in the direction the cue points anyway. Clickable scroll arrows would
need the cue columns to hit-test *differently* from what they cover, which is
the paint/hit-test divergence this whole note is about. Deferred, and probably
never.

**`left_column` is a *private* reader.** Settled by precedent rather than
argued here: `TextField`'s was made private in a376dd2 (2026-08-24) for exactly
this reason — "the horizontal scroll offset had no caller outside the field …
nothing above the field has a column to spend it on" — and its specs now read it
through `f.send(:left_column)`. The strips are the same case: an app cannot set
the offset (the strip owns the invariant) and has nothing to do with knowing it.
So: private `attr_reader :left_column`, `send` from the specs, and the class
rdoc names the offset without linking it (the doc site is `--no-private`).
Re-grow: publish when a real caller appears, on all three widgets, in one go.

**Unconditional; no flag.** No `scrolling: false` to keep clipping. The
framework's standing preference is no gate, and clipping-with-an-invisible-
selection shipped as a known rough edge, not as behavior anyone can depend on.

**Duplicate; no `AbstractStrip`.** This is the *second* copy of a ~15-line shell
(`segments` / `painted_width` / `extent` / offset / snap) across two components
that already diverge deliberately in paint — separator, bold, focus-gated
highlight (`D-menu-bar`: "deliberately painted *unlike* `Tabs`"). A base would
need hooks for `target`, for the cue glyphs and for the segment arithmetic, over
lines that are one expression each. The house rule is duplicate and re-argue at
the third copy (`D-float-field`, `D-select`); a third strip is not on the
horizon.

## Specs owed

- `left_column` is `0` in every pre-scrolling situation — the regression guard
  that this change is additive.
- arrow right into an off-screen tab scrolls the minimum; arrow back scrolls
  back; both ends clamp.
- a caption wider than the rect left-aligns and clips its tail, and does not
  oscillate across repeated syncs.
- click on a partially visible edge segment selects it *and* reveals it.
- hit test after scrolling resolves the segment actually painted under the
  point (the one-source guard), including on a cue column.
- CJK caption: an offset that would open on a wide glyph's right half snaps
  forward, and the painted row is exactly `rect.width` columns
  (`text_field_spec`'s `# 3 would open on 本's right half` is the model, and
  `send(:left_column)` is how it reads the offset).
- widening the rect until everything fits returns `left_column` to `0`;
  removing tabs re-clamps.
- cues appear/disappear at the right offsets and carry the covered cell's style.
- `MenuBar`: a cascade opened after scrolling anchors under the segment as
  painted; a click on a scrolled segment opens the right menu.

## Deferred

**Free scrolling (wheel, or a drag) is not in this.** `MouseEvent` can report
`:scroll_left` / `:scroll_right`, and a wheel over an overflowing strip could
move the offset without moving the selection — but that breaks the invariant
this note is built on: the very next `adjust_left_column` (any arrow, any click,
any resize) yanks the view back to the selection, which reads as the strip
fighting the user. Supporting it properly means a second state — "the user
scrolled, stop following" — with a resume rule, which is `List#auto_scroll`'s
`following?` machinery for a one-row widget. Re-grow it that way or not at all.

**Clickable cues** — see the chrome-not-buttons decision.

**A `MenuBar` overflow menu** (Vaadin's collapse-into-`»`) stays where
`D-menu-bar` left it: deferred, and now less needed.

## Graduation

- **`DECISIONS.md`** — amend `D-tabs`' "v1 clips the strip; scrolling is v2"
  block *in place* (it is the same decision, now resolved), and update its
  "Deferred" bullet and the closing "the strip clips rather than scrolls"
  consequence. `D-menu-bar` gets a pointer, since the ruling now spans both.
- **rdoc** — the `== Sizing` sections of `tabs.rb` and `menu_bar.rb` both
  currently promise clipping and document the limitation; rewrite. The
  paint/hit-test one-source note gains the offset.
- **book ch7** — same paragraph, reader-facing.
- **`TERMINOLOGY.md`** — a `left_column` row beside `scroll_top_row`.
- **`AGENTS.md`** — one line in *Nomenclature*: a horizontal scroller says
  `left_column` as a vertical one says `scroll_top_row`. That is the only part
  clearing the from-a-distance gate; everything else is per-symbol.
- **`CHANGELOG.md`** — *no new entry.* Both strips are still under
  `[Unreleased]`, so scrolling folds into the existing `Add Component::Tabs`
  and `Add Component::MenuBar` sentences (their one-sentence cap is the
  constraint); nobody upgrading has ever seen the clipping behavior. Same fact
  is why amending `D-tabs` in place is uncontroversial.
- **`rake sig`** — no public signature changes if `@left_column` stays private;
  run it anyway.
- **sampler** — a deliberately starved strip, and a PTY walk that arrows past
  the edge (key pacing rule applies).
- Retire this note.
