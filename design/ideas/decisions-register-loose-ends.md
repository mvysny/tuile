# Two questions the cull found but could not answer

**Status:** open, 2026-09-14. Left over from the cull of `design/decisions.md` (565 KB → 437 KB
→ 390 KB, 36 of 73 entries; the tail at ≤5.5 KB was deliberately declined once the measured yield
fell to ~5% of the file). Each of these needs a judgement the cull had no standing to make, so
they were flagged rather than fixed. Delete this file as each is settled.

## 1. Should `D_wrapping_field` split in two?

Its heading asks two questions — why `AbstractWrappingField`, and why `HasContent` — and the body
carries two arguments, which is why it stayed the largest of its group at ~7.3 KB after two passes.
Splitting it is register maintenance rather than compression, so the cull left it alone.

Against: both slugs are cited, and a split means a sweep plus the tripwire. For: an entry answering
one question is the register's whole shape, and the `HasContent` half is what the other entries
actually cite.

## 2. `D_cluster_width` contradicts itself about what a mis-measure costs

Bug (1) listed overrun, shift and desync as the symptoms; the entry's own asymmetry argument says
summing a cluster's parts *over*-measures, and classes that as cosmetic — one blank column, not an
overrun. Both cannot be right.

The cull dropped the symptom list as duplication and did **not** correct the argument, so the
tension is untouched, not resolved. Whoever settles it should check which direction the real
failure runs before rewording either half.
