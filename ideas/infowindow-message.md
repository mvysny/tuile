# InfoWindow — migrate the line-list body to `message=`

**Status:** seed, 2026-08-31. Direction agreed, not designed; spun off from
`ideas/confirm-dialog.md` (its "`InfoWindow` is inconsistent with the family"
question). Do after `ConfirmWindow` ships.

**The problem.** `InfoWindow` is ancient — born before `TextView` existed — so
it builds a **`List`** of lines, which *truncates* long lines, while
`ConfirmWindow.alert` renders a `TextView` body, which *wraps*. Two "here's
some information" paths behave differently on a long sentence.

**The agreed direction.** Adopt `ConfirmWindow`'s body seam: `message=`
accepting `Component | String | StyledString | nil`, the reader returning what
was assigned (the store-as-given rule from the confirm design), text coerced
to a wrapping `TextView`.

**Known costs to work through when picked up:**

- Breaking: the lines-array API dies. CHANGELOG **Breaking** entry plus the
  one migration sentence.
- Check whether `ConfirmWindow.alert` has already subsumed the *popup* use of
  `InfoWindow`, leaving only the tiled use to migrate (the confirm design's
  rejected option (c)).
- Book ch7 and the README components row frame `InfoWindow` as a scrollable
  list of *lines*; both need rewording.
