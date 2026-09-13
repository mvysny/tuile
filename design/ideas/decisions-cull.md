# Culling `design/decisions.md` — handoff

Working note for finishing a three-pass rework of `design/decisions.md`. Delete this file when the
cull is done; nothing here is a `D_` entry, and nothing about `design/` itself ever becomes one.

## Where this came from

`decisions.md` was 565 KB across 73 entries — bigger than the whole `book/` (229 KB) and 73% the
size of `lib/`. The `design-docs` skill (`~/.claude/skills/design-docs/`, and its `about.md`
chapter *Findings* for the why) prescribes three passes over a register in that state:

1. **Mechanical** — headings become questions, `Status:` paragraphs dissolve, the ADR skeleton
   flattens. **Done** in `a849adb`, before this work started.
2. **Homing** — what the rdoc already says is deleted rather than restated; what is about someone
   else's toolkit moves to `research.md` behind an `R_` the entry cites; cross-symbol rules move to
   `architecture.md`. Every road not taken is kept. **Done** in `91c4233`, `e9ff9ac`, `6a1b90a`,
   `b70aadf`.
3. **The cull** — a second party, later, with a number: read every entry, cut mercilessly, stop at
   **4 KB per entry**. **This is what remains.**

## State as of the last commit (branch `docs/design-docs-refresh`)

| file | bytes | note |
|---|---|---|
| `design/decisions.md` | 390 KB | was 565 KB, then 437 KB; 73 entries |
| `design/research.md` | 42.5 KB | was 7 KB; 18 `R_` entries |
| `design/architecture.md` | 5.8 KB | cap 12 KB |
| `AGENTS.md` | 29.6 KB | cap 34 KB |

`bash design/verify_design_tripwires.sh` exits 0. Keep it that way after every batch.

**36 of 73 entries are culled** — the whole worklist down to `D_mouse` (5.5 KB pre-cull). The 37
remaining are the ≤5.5 KB tail, which this file already says to sweep last and only where a
paragraph obviously restates its neighbour. Culled entries now sit at 4.5-9.5 KB; `D_tabs` stays
the largest at 9.5 KB on ~25 distinct roads.

**Check cites against `c2d8ac4:design/decisions.md`, never against `design/decisions.md`** — the
live file now holds culled text, so a diff against it compares the new prose to itself and reports
clean whatever was dropped. Two agents hit this independently. The cheap global check:

```bash
git show c2d8ac4:design/decisions.md | grep -oE '\b[DR]_[a-z][a-z0-9_]*' | sort -u > /tmp/pre.cites
grep -oE '\b[DR]_[a-z][a-z0-9_]*' design/decisions.md | sort -u | comm -23 /tmp/pre.cites -
```

**The homing pass is complete and should not be redone.** All 73 entries were read or scanned; 35
were rewritten, and the rest were checked and found to carry prior art as inline *citations* (which
is where a citation belongs) rather than as survey blocks. The seven surveys that moved became
`R_time_pickers`, `R_key_dispatch`, `R_visibility_flags`, `R_box_layouts`, `R_confirm_dialogs`,
`R_overlay_dismissal`, `R_row_vs_line`, `R_single_line_paste`; `R_glibc_locale`, `R_color_depth`,
`R_ambiguous_width`, `R_esc_ambiguity`, `R_dec_private_modes`, `R_ratatui` and `R_charm_ruby` grew
the Ruby, terminal and upstream facts the entries were carrying inline.

## What the cull is, and is not

**Is:** compressing prose. Every entry is already decision-shaped — a question, the answer, the
roads not taken as *why not* clauses, and a *cost we carry* close. The fat left is wordiness, not
misfiled content.

**Is not:** dropping roads. `about.md`'s `F_adr_immutability` is explicit that the rejected roads
are the thing the file exists to protect — a road deleted here is one that gets re-litigated from
scratch in two years. **If an entry cannot reach 4 KB without losing a road, leave it long and say
so.** 4 KB is the ceiling the cull stops at, not a target every entry must hit; the ruler
(`D_bg_inherit`, 4.3 KB) is what an entry trims *toward*.

Also do not touch: the `## D_<slug> — <question>?` heading shape (tripwired), any `D_`/`R_` cite
(tripwired), or the founding entry's position at the top.

## Method that worked

Editing one 437 KB file in place is painful. Split it, edit per entry, reassemble:

```bash
cd ~/work/my/tuile
S=<your scratchpad dir>            # session-specific; make a fresh one
mkdir -p $S/entries
awk -v out="$S/entries" '
  /^## D_/{ n++; f=sprintf("%s/%02d_%s.md", out, n, $2) }
  { if(n==0) print > (out "/00_preamble.md"); else print > f }
' design/decisions.md
cat $S/entries/*.md | cmp - design/decisions.md && echo "round-trip OK"
```

Then rewrite entry files with `Write`, and reassemble with
`cat $S/entries/*.md > design/decisions.md` before running the tripwire and committing. The
numeric prefix keeps `*` in file order. **Verify the round-trip before editing anything** — it is
the only guard against silently dropping an entry.

Commit every ~8 entries with the byte count in the message, and check the number against
`wc -c` rather than estimating it.

## Cut, then re-read — the second pass is not optional

Measured over 36 entries: **a first cut lands at 6-7 KB and stops, and it is always damaged.**
Sending the same agent back over its own output — re-read end to end, check coherence, then cut
again — caught, across the batches: a road whose *second* losing reason had been deleted rather
than compressed (eight separate instances); a merged bullet that introduced the claim "all three
lose to one reason", which the source never makes and which is false; four dangling antecedents;
a cost paragraph excluding `ComboBox` twice for two different reasons; a silently dropped cite;
a re-grow rule turned from conditional into an unconditional commitment; and two freshly
introduced rot-shaped claims in the agent's own replacement text.

Several entries came out **larger** after the re-read, because restoring half-protected roads
outweighed the further trims. That is the correct outcome: the ceiling is 4 KB, but the binding
constraint is that no road may lose a reason.

What separates the bytes, and the test to apply per paragraph:

- a **road** records a choice against an alternative — keep, as one sentence: the road named, the
  reason it lost, plus the fact that makes "we tried it" credible. Budget ~110-130 bytes. Where
  several roads lost for the same reason, name them together and give the reason once — but each
  must keep its own *specific* defect or the merge costs roads.
- a **ruling** states how the thing behaves. The rdoc owns it; it goes. Entries are padded with
  these at least as much as with roads, and the way to be sure is to open the rdoc: three entries
  turned out to be restating `Locale`, `Locale.system`, `DateFormats::REF` and `humanize`
  near-verbatim.

A road with one of its two defects left reads as an inconvenience rather than a defect, which is
exactly the re-litigation this file exists to prevent — it is worse than an entry at 6 KB.

## Worklist — entries over the 4 KB ceiling, largest first

Regenerate with `bash design/verify_design_tripwires.sh` (it prints per-entry sizes without
failing — that listing is the cull's worklist, by design).

13.3 D_tabs · 11.3 D_locale · 11.2 D_date_field · 10.5 D_select · 9.7 D_menu_bar ·
9.6 D_notification · 9.5 D_has_validation · 9.2 D_time_field · 8.6 D_confirm_window ·
8.4 D_placeholder · 8.3 D_bad_input · 8.0 D_wrapping_field · 7.8 D_outside_click ·
7.6 D_bg_surface · 7.6 D_boolean_fields · 7.5 D_box_layouts · 7.4 D_color_depth ·
7.4 D_key_dispatch · 6.7 D_visibility · 6.6 D_status_bar · 6.2 D_list_items ·
6.2 D_checkbox_group · 6.1 D_scrollbar_ink · 6.0 D_component_lookup · 5.9 D_no_hint_color ·
5.9 D_attach_hooks · 5.8 D_slots · 5.8 D_scroll_nomenclature · 5.6 D_radio_group ·
5.6 D_cluster_width · 5.6 D_on_blur · 5.6 D_bracketed_paste · 5.6 D_progress_bar ·
5.5 D_no_context_menu · 5.4 D_text_field_axes · 5.4 D_mouse · 5.3 D_component_contract ·
5.3 D_theme_ref · 5.2 D_cluster_caret · 5.2 D_hook_visibility · 5.1 D_empty_ancestor ·
5.0 D_integer_field · 4.9 D_float_field · 4.9 D_no_native_backend · 4.9 D_bigdecimal_field ·
4.9 D_text_view_scroll_verbs · 4.9 D_ambiguous_width · 4.8 D_text_area_rows ·
4.8 D_no_key_interceptor · 4.7 D_background_rgb · 4.7 D_input_filters · 4.7 D_kill_keys ·
4.6 D_color_slots · 4.6 D_screen_lifecycle · 4.4 D_text_area_columns · 4.4 D_combobox ·
4.3 D_overlay · 4.3 D_bg_inherit · 4.2 D_final_tree · 4.2 D_extent · 4.1 D_repaint_cascade ·
4.1 D_tree_api · 4.0 D_wrap_leading_space

The first eighteen hold most of the remaining fat: about 155 KB, which a cull to 5–6 KB each takes
to roughly 100 KB. Everything below ~5 KB is close enough that the reading is worth more than the
bytes — sweep it last, and only where a paragraph is obviously restating its neighbour.

## What the entries keep

Per entry, the shape to trim toward: the question; one paragraph of what forced the decision; the
answer and the principle it sharpened; each road not taken as a bold lead-in plus the reason it
lost (these are the bytes worth keeping); the costs accepted; any **re-grow rule** stating what
would reopen the question. Cut instead: restatements of what the rdoc documents, process narration
("the first cut", "amended", "refined during implementation") where only the *current* answer
matters, per-file line pointers like `list.rb:209`, and enumerations of theme values that live at
the value.

## Two things found on the way, worth keeping

- **The migration agent's "keep it as-is, the roads not taken are valuable" was circular** — it
  restated `decisions.md`'s own preamble. Measured, the roads were 22% of the file; the other 78%
  was rdoc restatement, upstream facts and status.
- **Some entries carried stale claims**, e.g. `D_integer_field` still said `content` / `content=`
  were public on the typed fields after `D_wrapping_field` removed them. Fix those where the cull
  finds them — a doc that is confidently wrong is worse than one that is merely long. Five more
  turned up in the first 36: `D_has_validation` counted six `default_bg_color` overrides where
  `lib/` has four; `D_outside_click` named `Popup#owner` for what is `Overlay#owner`; `D_mouse`
  said no component consumes the wheel, where `List` and `TextView` both scroll on it;
  `D_text_field_axes` still described the `TextArea` axis conflation that `D_text_area_columns`
  fixed; `D_radio_group` named `content` for what is `list`, and cited `List#lines=` for a
  behaviour documented on `List#items=`.
- **The claim shape that rots is the enumeration** — "no component but X", "all five call sites",
  what something "still" or "does not yet" does. Two agents introduced a fresh one while fixing an
  old one. State the standing rule instead of listing today's members.

## Open, for the owner

- `D_wrapping_field` lists "legitimate includers of `HasContent`: `Slot`, `Window`, `Overlay`",
  but `combo_box.rb:35` still includes it. Consistent with the entry's own "migrate `ComboBox`
  too" rejection, so the list may be prescriptive rather than an inventory. Left alone.
- `D_wrapping_field`'s heading asks two questions (`AbstractWrappingField` *and* `HasContent`) and
  carries two arguments; it is the largest of its group. A split into two `D_` entries is register
  maintenance, not a cull.
- `D_cluster_width`'s bug (1) symptom list (overrun/shift/desync) sat in tension with the entry's
  own asymmetry argument — summing parts *over*-measures, which the decision classes as cosmetic,
  not as overrun. The list was dropped, not corrected; the tension is untouched.
