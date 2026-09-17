# `CompositeField`: several fields behind one value

**Status:** filed 2026-09-04, as what was left over when
`Component::AbstractWrappingField` shipped and its note graduated — read
`D_wrapping_field` first, this note assumes it. Nothing here is built. **Its two
open questions are now answered** by the first consumer, which shipped
green-field rather than on this base: read `D_date_time_field` before touching
anything below. What is still open is only whether a *base* is worth extracting,
which needs a **second** consumer — a `start`/`end` range field is the candidate.

The shape: several fields arranged in a layout behind one typed value, as
`Component::DateTimeField` is over a `DateField` plus a `TimeField`.
`AbstractWrappingField` is deliberately *one editor, full stop*, and was built as
the prototype this learns from.

What is already known about its shape:

- **A sibling of `AbstractWrappingField`, not a subclass of it.** That base's
  whole value is that one child removes the layout and the ordering; inheriting
  from it would put both back.
- **No auto-discovery of the fields — ever.** A tree walk for "the fields inside
  me" would descend *through* a wrapping field into the private editor it exists
  to hide. Registration is explicit.
- **`active=` already gives it the right commit semantics** — see
  `D_wrapping_field`, where that seam is chosen partly *because* it survives
  here: focus moving between two of a composite's own fields keeps the composite
  active, so it does not spuriously commit. The one hard part it inherits solved.
- **The abstract pair generalizes by pluralizing.** `value` / `value=` already
  mean "read the value out of my field(s)" and "apply the value into my
  field(s)"; a composite changes nothing else about that contract, which is the
  evidence the prototype transfers.
- **It cannot inherit the "the base adds the child" guarantee**, and that is
  another reason it is a sibling. `AbstractWrappingField` calls `add_child`
  itself, which is what makes *own and hide* a guarantee rather than a
  convention. A composite must let its subclass populate a layout, so something
  else has to replace it — explicit registration of which descendants are its
  fields.
- **What it must solve, and a wrapping field never had to:** assembling `value`
  from several children with a diff guard; deciding whether `bad_input?` is "any
  child" or "the combination"; which child takes focus on `handle_focus`; and how
  the layout is expressed without becoming a container. `DateTimeField` answers
  all four for two halves — the first three as written code, the last by simply
  *being* the `Horizontal`, which is the answer a base cannot take.

**Which component wears the error — answered in `D_date_time_field`, and this
note's own reading of the background chain was wrong.** It read: `error_bg_color`
sits at the top of the same chain a child walks, so a child inherits its parent's
*error* level; verified with a bare `Label` under an invalid `IntegerField`,
which does come back `Color 88`. But a `Label` answers no level of its own, and
**every field answers `default_bg_color`** — which resolves *before* the parent
is consulted. So marking a composite self-invalid reddens the chrome around the
fields and leaves the fields flat, i.e. the opposite of what this note assumed.

The shipped answer: **the composite paints only the fault no half can wear**,
with its ink synced onto the halves as `BG_INHERIT` marks — which also settles
the BG_INHERIT question this note filed as a second one (the marks are *synced to
the condition*, not permanent, so the halves keep their own wells while the
composite is clean). And the genuinely hard case, a **combination** error
(`start > end`) where no single field is wrong, is exactly the one the composite
wears: honest rather than loud.

## Related

`D_wrapping_field` (the one-editor base this generalizes — its admission test,
its forwarding test, and `active=` as the commit point), `D_has_validation` and
`D_bad_input` (the two error channels a composite has to combine),
`D_caption_ownership` (why an inner label is chrome, and chrome is not what
failed), `D_bg_surface` (the background chain, and why a field child does not
inherit an ancestor's error level), `D_date_time_field` (the first consumer:
every question above answered for two halves, green-field).
