# `D_cluster_width` contradicts itself about what a mis-measure costs

**Status:** open, 2026-09-14. The last loose end of the cull of `design/decisions.md` (565 KB →
437 KB → 390 KB, 36 of 73 entries; the tail at ≤5.5 KB was deliberately declined once the measured
yield fell to ~5% of the file). It needs a judgement the cull had no standing to make, so it was
flagged rather than fixed. Delete this file once it is settled.

Bug (1) listed overrun, shift and desync as the symptoms; the entry's own asymmetry argument says
summing a cluster's parts *over*-measures, and classes that as cosmetic — one blank column, not an
overrun. Both cannot be right.

The cull dropped the symptom list as duplication and did **not** correct the argument, so the
tension is untouched, not resolved. Whoever settles it should check which direction the real
failure runs before rewording either half.
