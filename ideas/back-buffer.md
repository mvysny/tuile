# Back-buffer cell diff (flicker-free rendering)

Status: **proposal, for review**. Supersedes the stop-gap synchronized-output
commit (`23b4e71`), which we keep as a bonus but which only works where the
whole terminal stack implements DEC mode 2026 (notably *not* under tmux < 3.4).

## Problem

Components paint by emitting escape sequences straight to the terminal:

```ruby
screen.print TTY::Cursor.move_to(x, y), styled_string.to_ansi
```

When a frame redraws a large region — e.g. the full-scene repaint a shrinking
non-modal popup forces via `Screen#needs_full_repaint` — the terminal shows the
clear-then-redraw in progress. On the slash-command demo this flickers on every
keystroke. Mode 2026 hides it on capable stacks but is best-effort: one old
layer (tmux < 3.4, Alacritty < 0.13) silently swallows the private-mode set and
the flicker returns.

The durable fix is stack-independent: **never write a cell whose final value
equals what's already on screen.** Flicker comes from overwriting a cell with a
space and then the glyph; if the result is unchanged, emit nothing. This is why
ncurses, tmux, and Ratatui never flicker on any terminal.

## Approach P — single cell buffer + dirty-cell diff

Two stages, kept distinct:

- **Composite** (in memory): components write into a back buffer. Driven by the
  *existing* invalidation engine — only invalidated components repaint, so cost
  stays proportional to what changed.
- **Flush** (to terminal): walk the cells that actually changed, group them into
  runs, and emit `move_to` + minimal SGR per run. Only changed cells reach the
  wire.

Crucially this **keeps almost the entire current architecture** and swaps only
the output sink. We do *not* rip out invalidation or the z-order overdraw rule.

### What stays (deliberately)

- **`invalidate` / the `@invalidated` set.** Dedup, paint-at-most-once-per-frame,
  decides *who* repaints. Unchanged.
- **The z-order overdraw rule** (`repaint` partitioning tiled vs popup,
  `collect_subtree`, "repaint occluders on top in stacking order"). It orders
  writes into the shared buffer so a popup wins where it overlaps content.
  Unchanged.
- **`needs_full_repaint`.** Still called on popup close / shrink / move. It stops
  being a flicker source *because the diff filters it*: every component rewrites
  its cells, the vast majority equal what's already there → not marked dirty →
  not emitted. Only the newly-exposed region differs and gets flushed. So
  "invalidate everything" becomes cheap without deleting it.

### What changes

- New `Tuile::Buffer` (cell grid) — the screen mirror that components paint into.
- `Component#repaint` methods call `buffer.set_line(x, y, styled)` instead of
  `screen.print(move_to(x, y), styled.to_ansi)`. Mechanical, ~8 files.
- `Screen` flushes by diffing dirty cells instead of accumulating a
  `@frame_buffer` of escape strings.

### What it kills

- The whole class of clear-then-redraw flicker, on **every** terminal,
  independent of mode-2026 support.

## Cell & Buffer model

Reuse `StyledString::Style` as the per-cell style — it is already a frozen value
type (`fg/bg/bold/italic/underline/strikethrough`) and already knows how to diff
itself into minimal SGR (`StyledString#sgr_diff`, lifted into a shared helper).
This is the single biggest reason the refactor is tractable rather than a
from-scratch styling layer.

```
Cell = (grapheme: String, style: Style)
```

- Normal cell = one display column.
- A 2-column glyph (CJK/emoji) occupies cell `x` (glyph) and `x+1` (a
  continuation sentinel; the flush skips it since the glyph already advanced the
  cursor two columns, and overwriting either half clears both). `StyledString`
  already computes correct widths via `Unicode::DisplayWidth` and already drops
  half-overlapping wide chars on `slice` boundaries, so the hard Unicode work is
  done.

### `Buffer` API (new file `lib/tuile/buffer.rb`)

One top-level constant per file per the Zeitwerk rule; `Buffer::Cell` nested.

```ruby
buffer.set_line(x, y, styled_string)   # write a row, clipped to bounds — workhorse
buffer.set_char(x, y, grapheme, style) # primitive; marks the cell dirty iff it changed
buffer.fill(rect, style)               # clear_background's replacement
buffer.resize(size)                    # on WINCH; forces full redraw
buffer.flush -> String                 # emit minimal escapes for dirty cells, clear dirty
```

`set_line` is a near-mechanical replacement for today's
`screen.print(move_to(x, y), styled.to_ansi)`: walk the styled string with
`each_char_with_style`, place graphemes at successive columns, handle wide-char
continuations + clipping.

### Dirty tracking — proportional, no whole-buffer sweep

`set_char` compares the incoming `(grapheme, style)` against the current cell; on
a difference it overwrites and records the cell (or its row range) as dirty.
There is **no per-frame whole-buffer clear or copy** — un-repainted cells simply
retain last frame's value. So both composite and flush cost scale with what
actually changed, which is the efficiency property we want at large sizes
(210×79 ≈ 16.6k cells).

Minor accepted imperfection: a component that writes a cell away from and back to
its original value within one frame leaves it marked dirty, so the flush
re-emits an identical glyph to that one cell — imperceptible (same value, no
flash), and rare. Avoiding it would need a second buffer + full diff; not worth
the per-frame whole-buffer touch.

### Flush — reuse `StyledString` for the run emitter

Walk dirty cells in row order, group maximal horizontal runs, build a
`StyledString` from each run's `(grapheme, style)` cells, and emit
`move_to(run.x, run.y)` + `run.to_ansi`. `StyledString` already collapses
adjacent same-styled characters and emits minimal-diff SGR, so the run encoder is
nearly free. Wrap the whole flush in `Ansi::SYNC_BEGIN`/`SYNC_END` (belt and
suspenders where supported).

## Performance

With composite proportional to invalidation, a keystroke that changes one widget
touches a few hundred `set_char` and emits a few runs — sub-millisecond. The only
potentially full-width operation is the dirty scan on flush; track dirty as row
ranges (or a dirty-row set) so it stays proportional. No C sidecar now; if the
diff scan ever shows in a profile it is the most mechanical thing to drop into C
later, but it is unlikely to matter at keystroke cadence.

## Deferred: per-component back buffers + compositor

A later optimization, **not** in this plan. Each component would own a buffer;
the screen is composited by walking a z-stack over dirty regions. Honest
assessment of why it waits:

- It does **not** avoid clipping — it adopts clipping's tamer cousin
  (z-compositing) and forces a **transparency model** (components don't tile
  their rect — see the "not required to fully tile" invariant — so cells need
  set-vs-transparent so lower layers show through). That's *more* model
  complexity than Approach P, where the parent's clear-fill + shared buffer
  already handles gaps.
- The waste it would save is mostly already gone. Obscured-component-under-dialog
  splits two ways under Approach P:
  - *Only the dialog changes* (the actual slash-menu case): only the dialog is
    invalidated, so the obscured component is **not repainted at all**.
  - *The obscured component changes*: the overdraw rule repaints the dialog on
    top, but only its `repaint()` **CPU** — the diff drops its unchanged cells
    from the wire.
  Per-component buffers would shave only that residual CPU, by copying the
  dialog's buffer cells instead of re-running its `repaint`.

It genuinely pays in exactly one regime: high repeat-rate scroll (held arrow /
mouse wheel) of a large component on a large screen, where re-rendering content
each repeat is the cost. Keep the door open: design `Buffer`'s API so components
paint through a drawing surface (`set_line`/`set_char`) without knowing whether
it is the global buffer or their own — then a compositor becomes a drop-in if
profiling ever demands it.

## Migration surface

Eight files emit paint output today: `component.rb` (base `clear_background`),
`label`, `button`, `list`, `text_field`, `text_area`, `text_view`, `window`.
Each has 1–3 `screen.print(move_to, ansi)` sites. Rewrite is mechanical:
`screen.print(move_to(x, y), styled.to_ansi)` → `buffer.set_line(x, y, styled)`.
Borders (Window) and row highlights (List `with_bg`) remain per-row styled
strings, so they compose unchanged.

## Test-suite impact (the bulk of the human effort)

`FakeScreen` captures emitted bytes in `@prints`; many specs assert
`screen.prints.join.include?("hi")`. After the change components write to a
buffer, not `print`. So:

- `FakeScreen` exposes the back buffer; new idiom
  `assert_includes screen.buffer.row_text(2), "hi"` — cleaner than scanning
  escape soup.
- Specs asserting raw `prints` (a meaningful fraction across the 8 component
  specs) migrate to buffer queries. Add `Buffer#row_text(y)` / `#cell(x, y)`.
- New `spec/tuile/buffer_spec.rb` covers the cell model, wide-char
  continuations, clipping, and the diff — including the load-bearing property:
  **an unchanged cell emits nothing**.

This test migration is larger than the production rewrite.

## Phasing (keep `rake spec` green at each step)

1. **`Buffer` + `Cell` + flush, standalone.** New files + full unit spec. Zero
   integration. Lift `StyledString#sgr_diff` into a shared SGR helper both use.
   *Lands green, touches nothing else.*
2. **Wire `Screen` to composite into the buffer and flush by diff.** Keep
   `Component#repaint` writing through a thin `set_line` shim so the change is
   one layer. Switch `FakeScreen` to expose the buffer.
3. **Migrate component `repaint`s** to `set_line`, one file at a time, migrating
   each mirrored spec alongside.
4. **Simplify `Screen#repaint`'s output path** (drop `@frame_buffer`
   accumulation; the partition/overdraw logic and `needs_full_repaint` stay).
   Update the AGENTS.md "Invalidation + repaint" section to describe the
   buffer + diff sink.
5. Re-profile; confirm no flicker on Alacritty **and under tmux** (the acceptance
   test the mode-2026 stop-gap fails).

## Open decisions (resolved during design discussion)

- **Keep `invalidate`** — yes. Composite proportional to change; lower-risk
  refactor than full recomposite.
- **Flush emits only changed runs** — yes; reuse `StyledString.to_ansi`.
- **Per-component buffers** — deferred; API kept open (see above).
- **`Style` location** — reuse `StyledString::Style` as the cell style, one
  styling vocabulary across the framework.
