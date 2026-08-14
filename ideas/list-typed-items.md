# Typed items + a renderer on `List`

**Status:** design agreed 2026-08-14, **not implemented**. Both forks settled:
rendering is **lazy** (viewport-only, memoized), and the four composers
(`ComboBox`, `Select`, `RadioGroup`, `CheckboxGroup`) **fold in** in the same
change. What's left below the line is a handful of genuinely open questions.

This is the first half of `ideas/new-components.md`'s infrastructure item 6
("Typed items + data provider on `List`"), which gates List Box, Grid and
Virtual List. The *data provider* half is explicitly out of scope here — but
lazy rendering is what keeps it reachable later without a second redesign.

## Why

`List` is Tuile's one generic component that still takes pre-rendered rows, and
it shows in two places.

**1. Every internal consumer already discards the row and resolves the index
against its own array:**

```ruby
list.on_item_chosen = ->(index, _line) { select_at(index) }                    # radio_group.rb:80
list.on_item_chosen = ->(index, _line) { toggle_at(index) }                    # checkbox_group.rb:78
list.on_item_chosen = ->(index, _line) { select_option(@options[index].key) }  # picker_window.rb:42
@overlay.on_item_chosen = ->(index, _line) { commit(index) }                   # combo_box.rb:55, select.rb:75
```

Six sites of `->(index, _line) { @items[index] }`. AGENTS.md's own rule — "an
index is how a selection is *resolved*, never how it is *stored*" — is being
obeyed by hand, five times, because the framework hands back a string.

**2. Four hand-rolled copies of the `@items` / `@item_label` / `label_for` /
`rebuild_rows` shell** (ComboBox, Select, RadioGroup, CheckboxGroup).
`D-select` says a *fourth* copy is when to re-argue the shared base; we're
there. The answer isn't a base class — it's that the generic component should
have externalized rendering all along (`cop`: a `Grid<T>` takes a renderer, a
domain component takes data).

Secondary win: `rebuild_padded_lines` is O(all rows) on every `lines=` **and
every width change**. A 50k-row `LogWindow` re-ellipsizes all 50k rows on every
terminal resize today. Lazy rendering deletes that.

## The API

```ruby
list.items    = people                 # arbitrary objects; one item = one row
list.renderer = ->(p) { StyledString.plain("#{p.name} ") + screen.theme.hint(p.email) }
list.on_item_chosen    = ->(index, item) { open(item) }
list.on_cursor_changed = ->(index, item) { detail.person = item }   # item nil when off-content
```

- `renderer` is `item -> StyledString | String | #to_s`, defaulting to the
  current coercion (`StyledString.parse(item.to_s)`), so a `List` of plain
  strings needs no renderer at all.
- Signature is `->(item)`, **not** `->(item, index)`. Neither group needs the
  index (they know their own `value`). Re-grow only on a real caller.
- Renderer output is **one row**. See open question (2) on `\n` in it.

### `lines=` survives as line-flavored sugar — and that's the whole compat story

`lines=` keeps its `\n` split and rstrip, and stores the resulting
`StyledString`s **as the items**, with the identity renderer. So for a
line-populated list *the item is today's `StyledString`*, and:

- `sampler.rb:394`'s `->(_idx, line) { accept(line.to_s) }` keeps working —
  the second callback arg is byte-identical to before.
- `LogWindow#add_line("a\nb")` still yields two rows (the split stays in the
  line-flavored setters; `items=` never splits, because the cursor index *is*
  the item index).
- `list_spec`'s 156 `lines` references mostly stand.

`items=` is the primary API; `lines=` / `add_line` / `add_lines` stay,
documented as "items that are their own rendering".

## Lazy rendering

Render only the `rect.height` rows in the viewport, memoized per index, cache
dropped wholesale on `items=` / `renderer=` / `on_width_changed` /
`scrollbar_visibility=`.

Deleted: `@padded_lines`, `@blank_padded`, `rebuild_padded_lines`, the
incremental `@padded_lines +=` in `add_lines`, and `on_width_changed`'s rebuild
(the hook still nukes the cache). `paintable_line` becomes render → pad →
highlight → scrollbar glyph, with the memo between render and pad. Net line
count should go *down*.

Two prices, both worth naming in the rdoc:

- **Search renders candidates as it scans.** `select_next` matches on the
  rendered text (what the user actually sees). Worst case O(n) renders on a
  miss. **Search must render *without* populating the memo** — otherwise one
  failed search over a 100k-item list caches 100k rows. Paint memoizes; search
  doesn't.
- **A renderer doing IO is now a per-frame footgun.** The memo absorbs the
  repeat within a width, but "renderer runs at paint time" is a contract change
  from "renderer runs once at `items=`" and must be documented as such. (COP
  explicitly blesses a component reaching a service directly, so someone *will*
  put a query in there.)

## The composer fold

- **`RadioGroup` / `CheckboxGroup`** — delete `@items`, `items=`, `label_for`,
  `rebuild_rows`, and index resolution in `select_at`/`toggle_at`. `items` /
  `items=` delegate to the list; `item_label=` installs a list renderer that
  wraps the label with the `(*) `/`[x] ` prefix from the current `value`.
  `value=` then just `invalidate`s instead of re-rendering every row — the
  prefix is re-derived at paint. `on_item_chosen` hands the item straight to
  `self.value =`. See open question (5): the clamp.
- **`ComboBox`** — keeps `@items` and `@item_label` (it owns filtering, and
  `display_for` feeds the *field's* text, not a row). `refill` becomes
  `@overlay.items = @filtered` with `@overlay.renderer = @item_label` set once
  in the ctor; `commit(index)`'s `@filtered[index]` becomes `commit(item)`.
- **`Select`** — same shape; `@overlay.items = @items`. Its label measuring
  stays caller-side (`max(widest + 2 (+1), rect.width)`) — see non-goals.
- **`ListDropdown`** — gains `items=` / `renderer=` forwarders alongside
  `lines=`.
- **`PickerWindow`** — `items = @options`, renderer builds
  `"#{key} #{hint(caption)}"`, `on_item_chosen` gives the option; drops the
  `@options[index]` lookup.
- **`InfoWindow`, `LogWindow`, `file_commander`** — untouched (all line-based;
  `file_commander` could take items later, out of scope).

## Non-goals / re-grow rules to write into the decision

- **No measuring on `List`.** No `preferred_width`, no "widest item" reader,
  even though `Select` wants one — that reopens the top-down layout rule
  (v0.9.0). A caller-side query is the sanctioned shape and `Select` already
  has one.
- **No data provider yet.** `items` is an `Array`. Lazy render is the
  enabler, not the feature.
- **No `search_text` / matcher proc yet.** Match the rendered text.
- **No renderer index arg.**

## Open questions

1. **`lines` reader.** Alias of `items` (honest for line lists, a lie for typed
   ones), or drop it, or make it "the rendered rows" (forces a full render)?
   Leaning: alias, documented.
2. **`\n` in renderer output.** Clip to the first line, or raise? A literal
   `\n` reaching the buffer corrupts the frame, so silence isn't an option.
   Leaning: clip (cheap, matches `lines=`'s rstrip-ish forgiveness); raising is
   defensible since it's a programming bug.
3. **Does `items=` keep the `TypeError unless Array` guard?** Probably yes, but
   it forecloses passing a lazy enumerable later. Cheap to relax, not to
   tighten.
4. **`item_label` (groups) vs `renderer` (List) — two proc names, one concept.**
   Defensible (domain label vs. row rendering) but worth a sentence in the book
   so nobody hunts for `List#item_label`.
5. **Cursor clamping on `items=`.** AGENTS.md pins that `List#lines=`
   *deliberately* leaves a stale cursor alone, and `RadioGroup#items=` clamps
   before the rebuild so the single `on_cursor_changed` reports the final row.
   If `items=` delegates to the list, where does the clamp live? Either the
   groups clamp after delegating (preserves List's documented behavior), or
   `List#items=` starts clamping (cleaner, but a behavior change for
   `LogWindow`-shaped users and it breaks the "before the rebuild" ordering the
   RadioGroup comment relies on). Leaning: groups clamp; keep List's rule.
6. **`@last_cursor_state` now compares items with `==`.** Same semantics as
   today for strings; formalizes the "items need stable `#hash`/`#eql?`"
   requirement `CheckboxGroup` already carries. Just needs documenting.

## Side effect on `ideas/scrolling-nomenclature.md`

That note's table lists List's *content unit* (concept 1) as `line`. This change
makes it `item`, and leaves List's concept (2) — the wrapped unit — identical to
(1), as it already is. One less vocabulary to unify; worth folding into that
brainstorm before it's settled.

## Blast radius / rough plan

1. `List`: `items` + `renderer`, lazy render + memo, `lines=` re-expressed on
   top. Rename internals `@lines`→`@items`, `line_count` stays (scrollbar).
2. `spec/tuile/component/list_spec.rb` (1533 lines, 156 `lines` refs) — the
   line-based examples should survive nearly verbatim; add an items/renderer
   context, a lazy-render-count spec (renderer called ≤ viewport size), a
   search-doesn't-memoize spec, and a width-change-drops-cache spec.
3. Fold the five composers + their specs.
4. `rake sig` (public signature change → CI gates `sig/` drift).

## Graduation

- **Decision half** → `DECISIONS.md` `D-list-items`: why the renderer instead
  of a shared base for the fourth copy; why lazy over eager (the resize cost,
  the data-provider path) and its two prices; the non-goals above with their
  re-grow rules.
- **Invariant half** → AGENTS.md: renderer runs at paint (don't do IO in it);
  search renders without memoizing; one item = one row; no measuring on `List`;
  the cursor-clamp rule as settled in open question (5). Also update the
  "composes a `List`" paragraph in the `HasValue` section — the three things a
  future composer must repeat shrink to one (install a cursor).
- **User half** → book ch7 (`List` as a component, the `item_label` vs
  `renderer` note) and the per-symbol rdoc.
- **CHANGELOG** → one `Add` sentence for `items`/`renderer`, one `**Breaking:**`
  if `on_item_chosen`'s second arg changes meaning for any non-line list (it
  doesn't for line lists — say so in the migration half-sentence).
- Then update `ideas/new-components.md`'s infrastructure item 6 to "half done"
  and **delete this file**.
