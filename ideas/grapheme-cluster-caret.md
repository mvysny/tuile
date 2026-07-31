# Grapheme-cluster caret — redefine the editing axis

**Status:** parked 2026-07-31, deliberately. Designed in conversation right
after `D-text-field-axes` landed (commits `0f5219b`, `880ef7f`); parked so
TextArea's column fix — which does **not** depend on this — can land first.
Backward-incompatible on purpose; Tuile isn't stable yet.

## The problem this fixes

`@caret` in `AbstractStringField` indexes **codepoints**; the terminal draws
**grapheme clusters**. Every edit steps by one codepoint, so a multi-codepoint
cluster can be entered, split and half-deleted. Measured, on `master`:

| symptom | evidence |
|---|---|
| RIGHT stalls | `"éx"` (decomposed é), 3× RIGHT → cursor columns `[0, 1, 1, 2]` — 3 presses, 2 moves |
| BACKSPACE mutilates | `"é"` → `"e"` (accent stripped: a valid, *wrong* letter). `"🇯🇵"` → `"🇯"`. `"👍🏽"` → `"👍"` |
| DELETE orphans | `"é"` caret 0 + DELETE → text is a lone U+0301: `empty?` is false, paints as `""` (`Buffer#set_line` drops a zero-width grapheme with no base) |

Reachable by **typing**, not just `text=`: `Keys.printable?` admits combining
marks, regional indicators, variation selectors and skin-tone modifiers. Only
ZWJ is blocked (category `Cf`, caught by `\p{C}`) — so ZWJ families can't be
typed but arrive fine through `text=`.

## The insight

Today's naming describes the *storage*, not the user's unit. "Characters" is a
codepoint count — an implementation fact about Ruby's `String`. Nobody edits in
codepoints. The two meaningful units are **what the user edits in** and **what
the terminal paints in**, and the current design names one of them wrong.
`D-text-field-axes` fixed the conversions but kept the wrong name on the edit
axis.

## The proposal — caret indexes a boundary table

Reinterpreting `caret` as a cluster ordinal *over a String buffer* makes things
worse: Ruby's String API is codepoint-indexed all the way down (`insert`,
`slice!`, `[]`), so you get **three** axes and two conversion pairs
(cluster → char → column). A regression from today's two.

Instead: **one walk builds a boundary table; the caret indexes the table, and
each row carries both other axes.**

```ruby
# built by one each_grapheme_cluster walk, plus an end sentinel;
# cached and invalidated in on_text_mutated (same pattern as
# TextArea's @display_rows)
@boundaries = [{ offset: 0, column: 0 },
               { offset: 1, column: 1 },   # after "h"
               { offset: 3, column: 2 },   # after a decomposed "é"
               { offset: 4, column: 4 }]   # after a wide CJK glyph
```

- `caret` indexes the table → stepping is `± 1`. No snapping, no
  direction-aware prev/next helpers, no mid-cluster state to tolerate.
- `@boundaries[caret][:offset]` — char offset, for mutation.
- `@boundaries[caret][:column]` — terminal column, for the cursor.
- a clicked column resolves by scanning the table's `column` field.

Nothing ever adds a value from one axis to another, because the caret isn't
*on* either derived axis — it names a row holding both. This should collapse
TextField's `column_at` / `index_at` into table lookups and make
`AbstractStringField` **smaller**.

**Keep `@text` as the buffer of record; derive the table.** Do *not* store an
Array of clusters — see backfire 2.

## How it backfires

1. **Silent breakage at every `caret = <something>.length`.** The big one. Five
   in `lib/` (`combo_box.rb:245`, `integer_field.rb:62`, `text_area.rb:64,233`,
   `text_field.rb` ENDS_) and one in app code:
   `examples/sampler.rb:698: area.caret = start + command.length + 1` — adding a
   `String#length` to a caret. All keep working for ASCII and go wrong for
   anything else: exactly the failure mode `D-text-field-axes` deleted, relocated
   from the framework to its callers.
   **Mitigation — the one open decision below.**
2. **Insertion is where cluster-native storage bites back.** Today, typing a
   combining mark after `e` merges into `é` for free, because `String#insert`
   doesn't know about clusters. With an Array-of-clusters buffer, naive insertion
   yields `["e", "◌́"]` — two clusters, the second a lone mark painting as
   nothing — so you'd re-segment the neighborhood every keystroke. **String
   storage gets insertion right and stepping wrong; cluster storage inverts
   exactly that.** Hence: String buffer + derived table.
3. **`"\r\n"` is ONE grapheme cluster.** Verified: `"a\r\nb".grapheme_clusters
   == ["a", "\r\n", "b"]`. Any cluster-iterating code testing `c == "\n"` fails
   on it — TextArea's `compute_display_rows` does exactly that. Becomes
   `end_with?("\n")`, or normalize line endings on input. (Related pre-existing
   wart: a pasted CRLF arrives as ENTER + CTRL_J and `insert_char` turns it into
   *two* newlines.)
4. **`max_text_length` silently changes meaning** — characters → clusters.
   Arguably an improvement (a user who types `é` shouldn't burn two of ten) but
   a documented semantic change, not free.
5. **Two things it does NOT fix**, so don't credit it with them:
   - the cluster-**width** bug: `Buffer.display_width("👍🏽") == 4` while
     terminals draw it as 2 columns, and `Buffer#put_char` only models `w == 1`
     and `w == 2` (for `w == 4` it writes one cell, no continuation, and callers
     advance 4 → stale cells + cursor desync). Lives in `Buffer`, own job, own
     DECISIONS entry, `D-ambiguous-width` family.
   - TextArea's column-vs-count wrap. This model makes it *easier* (you iterate
     clusters with widths in hand) but doesn't perform it.

## What improves by construction

The DELETE-orphan bug becomes **unreachable** — you can't delete half a cluster
when the caret can't address half a cluster. The symptom disappears rather than
being fixed, which is the sign the abstraction is load-bearing.

## Measured, so nobody re-benchmarks it

```
480-char line: 62µs per grapheme_clusters segmentation (10k in 0.62s)
each_grapheme_cluster walk: same cost
```

We *already* pay a full walk per conversion in TextField today, so a
cached table is a net win, not a cost. Not a performance question at these
sizes.

## Open decision — loud or quiet migration

Renaming `caret`'s companions so stale `caret = text.length` call sites break at
**load time** costs churn in ComboBox, IntegerField, TextArea and the sampler.
Keeping the current spelling is less churn but leaves the silent-for-ASCII
hazard of backfire 1. **Recommendation: take the churn** — drop `text.length`
from the caret vocabulary and name the intent (`caret_to_end`, or an explicit
`cluster_count`), so an unconverted call site is a `NoMethodError` and not an
off-by-N. Not yet decided by the author.

## Scope note

Touches `AbstractStringField` (the shared base), so it lands on TextField **and**
TextArea at once. If done *after* TextArea's column fix (the plan), TextArea's
wrap will already be cluster-iterating with widths in hand, and the delta there
is switching its row records' `start`/`length` from char offsets to table
indices — mechanical. Land as two commits: base + TextField, then TextArea.

## On graduation

- book ch7 — rewrite the two-axes paragraph in reader terms (the edit unit is
  what you see, not what Ruby stores).
- AGENTS.md — the glyph-width invariant bullet, replacing "a text index is not a
  column" with the boundary-table rule; drop the "TextArea still has all three"
  note if it's fixed by then.
- DECISIONS.md — a new entry superseding the axis half of `D-text-field-axes`
  (which stays: it owns scrolling and `max_text_length`). Record backfires 1–3
  as the roads-not-taken, especially cluster-array storage.
