# InfoWindow — add the `message=` body seam, keep `lines=` as the rows body

**Status:** direction agreed 2026-08-31, not implemented. Spun off from the
`ConfirmWindow` design (`D_confirm_window`); unblocked since `ConfirmWindow`
shipped 2026-08-31.

**The problem, reframed.** `InfoWindow` is ancient — born before `TextView`
existed — so it builds a **`List`** of lines, which *truncates* long lines,
while `ConfirmWindow.alert` renders a `TextView` body, which *wraps*. The
original framing called that a bug; the agreed reframe: truncation is the
legitimate *rows* presentation (columnar reports, aligned listings — `TextView`
has no truncate mode, so `List` is the only way to show them). The actual bug
is that wrap-vs-truncate was **accidental** — decided by which class you
reached for, not chosen.

**The agreed direction — two presentations, one body slot, non-breaking:**

- `message=` — the *prose* body: `Component | String | StyledString | nil`,
  text coerced to a wrapping `TextView`, reader returning what was assigned
  (`D_confirm_window`'s store-as-given rule). Copy two of `ConfirmWindow`'s
  coercion — duplicated per the shallow-shell rule, well under fold-at-four.
- `lines=` — the *rows* body, kept alive: builds a `List` and assigns it
  through the same slot (effectively `self.message = list`, so `message` reads
  the `List` back — honest, and `List` deliberately has no `lines` reader so
  there is no symmetry to preserve). Delegate to `List#lines=` so the
  `\n`-split/rstrip semantics stay one implementation.
- Last writer wins; the constructor and `.open` type-dispatch the body
  positional: `Array` → rows, `String`/`StyledString` → prose, `Component` →
  as-is. Existing call sites all pass arrays, so nothing breaks — the
  CHANGELOG entry becomes **Add**, not **Breaking**.

**Decided:**

- **`ConfirmWindow#message=` does NOT learn Array→List.** A confirm dialog's
  body is prose by nature; hold off until a caller exists. (Noted so the
  asymmetry is a decision, not an oversight. If it ever comes: a List of lines
  is measurable — widest-line × row-count, no wrap pass — so it wouldn't fall
  into the "Component body ⇒ full half-screen box" hole.)
- **`InfoWindow` earns its row next to `ConfirmWindow.alert`:** tiled use, a
  buttonless popup, `declared_size:` control, and the rows presentation.

**To observe before hardening the API:** whether `../virtui` and
`../pikuri-tui` reach for `message=` or `lines=`. As of 2026-08-31 **neither
uses `InfoWindow` (or `ConfirmWindow`) at all** — both are on tuile ≥ 0.13 —
so the observation is about future adoption, and a breaking design would have
cost nothing downstream; keeping `lines=` is a preference for the rows
presentation, not a compatibility need.

**Costs when picked up:**

- Book ch7 and the README components row frame `InfoWindow` as a scrollable
  list of *lines*; both reword to "a Window with a body: prose that wraps
  (`message=`), or rows that don't (`lines=`)" — `message=` as the headline,
  or everyone keeps reaching for the truncating path and the original
  complaint survives in practice.
- Migrate the prose-shaped examples to `message=` to model the new default —
  `file_commander`'s `[path, e.message]` wants wrapping (long paths truncate
  today); the sampler pane should demonstrate both presentations.
- Out of scope: `.open` measuring like `ConfirmWindow`'s `MeasuredPopup`
  instead of defaulting to `Fraction::HALF` — `declared_size:` already covers
  it.
