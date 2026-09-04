# `CompositeField`: several fields behind one value

**Status:** filed 2026-09-04, as what was left over when
`Component::AbstractWrappingField` shipped and its note graduated — read
`D_wrapping_field` first, this note assumes it. Nothing here is built, and it
waits for a **real consumer**: the two questions it turns on have no answer
that today's components would test.

The shape: a `DateTimeField` over a `DateField` plus a `TimeField`, i.e. several
fields arranged in a layout behind one typed value. `AbstractWrappingField` is
deliberately *one editor, full stop*, and was built as the prototype this learns
from.

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
  child" or "the combination"; which child takes focus on `on_focus`; and how
  the layout is expressed without becoming a container.

**The hard one: which component wears the error, and it is already half
answered.** Picture `Date: [DateField] Time: [TimeField]` — a `Horizontal` of
four children, two of them labels. Two strategies: the composite marks *itself*
invalid, or it marks each of its *fields*. **They are not symmetric — the first
is already broken by the background chain.** `error_bg_color` sits at the top of
the same chain a child walks, so a child inherits its parent's *error* level,
not merely its normal well. Verified:

```ruby
f = Component::IntegerField.new
f.error_message = "nope"
label_under_it.effective_bg_color   # => Color 88 — the error well
```

So a composite that marks itself reddens its `Date:` and `Time:` labels, which
is wrong for the same reason `D_caption_ownership` keeps a caption off a field:
that text is chrome, and chrome is not the thing that failed. That points at
marking the fields — but it leaves the genuinely hard case open, and it is the
case a composite exists for: a **combination** error (`start > end`) where no
single field is wrong. Marking one is a lie, marking all of them is loud, and
marking none loses the signal. Unsolved, and the reason the whole area waits for
a real consumer.

**BG_INHERIT is the same question wearing a different hat** — does a composite's
whole subtree inherit its well (and the labels sit in it), or only the fields
(and the layout's gaps show terminal default, looking patchy)? Both readings are
defensible, neither has a consumer, so nothing guesses yet.

## Related

`D_wrapping_field` (the one-editor base this generalizes — its admission test,
its forwarding test, and `active=` as the commit point), `D_has_validation` and
`D_bad_input` (the two error channels a composite has to combine),
`D_caption_ownership` (why an inner label is chrome, and chrome is not what
failed), `D_bg_surface` (the background chain that makes "mark self" redden the
labels), `ideas/date-field.md` (`DateTimeField` is the plausible first
consumer).
