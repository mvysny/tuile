# InfoWindow — migrate the line-list body to `message=`

**Status:** seed, 2026-08-31. Direction agreed, not designed; spun off from
the `ConfirmWindow` design (`D_confirm_window`). `ConfirmWindow` shipped
2026-08-31, so this is unblocked.

**The problem.** `InfoWindow` is ancient — born before `TextView` existed — so
it builds a **`List`** of lines, which *truncates* long lines, while
`ConfirmWindow.alert` renders a `TextView` body, which *wraps*. Two "here's
some information" paths behave differently on a long sentence.

**The agreed direction.** Adopt `ConfirmWindow`'s body seam: `message=`
accepting `Component | String | StyledString | nil`, the reader returning what
was assigned (`D_confirm_window`'s store-as-given rule), text coerced to a
wrapping `TextView`.

**Known costs to work through when picked up:**

- Breaking: the lines-array API dies. CHANGELOG **Breaking** entry plus the
  one migration sentence.
- Check whether `ConfirmWindow.alert` has already subsumed the *popup* use of
  `InfoWindow`, leaving only the tiled use to migrate.
- Book ch7 and the README components row frame `InfoWindow` as a scrollable
  list of *lines*; both need rewording.
