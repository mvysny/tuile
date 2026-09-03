# Who owns a field's caption and its error — the field, or the layout around it?

**Status:** filed 2026-09-03 and **deliberately not brainstormed.** Split out
of `ideas/bad-input.md` so that note could stay on the field's own report;
this one is
parked on purpose. What follows is the question stated properly plus the facts
already in hand, so that whoever picks it up does not re-derive them. **There
is no recommendation here, and adding one is the work, not a formality.**

## The question, in one line

Does a field carry its own caption and paint its own error state, or does the
container it sits in own both?

Two shapes, both shipped by Vaadin at different times, which is what makes this
a real fork rather than a preference:

- **Vaadin 8 style — the field owns it.** `field.setCaption("Name")`,
  `field.setComponentError(...)`; the component renders its own label and its
  own error indicator. In Tuile terms: `TextField` includes `HasCaption`, and
  paints the caption and an invalid ink inside its own rect.
- **Vaadin 25 style — the container places it.** The form item owns the
  geometry: `formLayout.addFormItem(field, "Name")`. In Tuile terms:
  `FormLayout#add(field, caption: "Name")`, the caption and the error line are
  the *layout's* cells, and `TextField` does **not** include `HasCaption` — it
  paints a value and nothing else.

The two answers propagate: they decide whether `HasCaption` reaches the fields
at all, who reads `bad_input_message`, where the rules' message is stored,
whether a field needs an invalid ink of its own, and where a future
required-indicator lives.

## Facts already established, so they don't get re-derived

- **`HasCaption` exists and is a mixin**, but today a caption is *chrome the
  widget paints inside itself* — a `Window` title, a `Button` label. So the
  question is not "does Tuile have captions"; it is narrower: **may a caption
  be a label that sits *outside* the captioned component?** Note AGENTS.md's
  rule that the seam stays a mixin so a tree walk can find "the Button
  captioned Submit" — an answer that moves captions onto the container has to
  say what that lookup becomes.
- **The caption/value line is already drawn:** `caption` is app-authored
  chrome, `text` is the user-editable value, and a component may carry both
  (AGENTS.md, "Input values"). Nothing here reopens that.
- **Top-down layout is the heaviest prior, and it points at the container.** A
  field is handed one row by its parent and cannot grow a second one for a
  caption or an error message; advertising a wanted height is the deleted
  bottom-up channel. So whoever paints the extra rows must be whoever owns the
  geometry — which is an argument the Vaadin-8 shape has to answer, not one it
  can wave off. `D_status_bar` says the same thing from the other side: the
  framework reserves no row it wasn't asked for.
- **The field-side half has *shipped*, and it is smaller than it first
  looked.** `Component::HasBadInput` (`D_bad_input`) reports one fact —
  `bad_input_message`, on the fields whose input can outrun their value — and
  paints nothing. Everything about a *rule's* verdict was handed to this file;
  see the section below. What did not ship is the *push* notice, deliberately:
  its only consumers are displays, so it lands with whatever this file decides,
  and it is why `ideas/bad-input.md` still exists.
- **The ink question comes with this file** (it was
  `R_invalid_ink_is_not_a_background` in the bad-input note). `invalid` and
  `focused` **co-occur**, so an invalid
  background accent puts two meanings in one channel and owes a 2×2 precedence
  ruling; `BG_STATES` is closed and framework-defined (`D_bg_surface`).
  `Style` already models fg, `bold`, `underline` and SGR 7 (`D_inverse`), so a
  red fg or an underline is available without inventing a channel. A red fg
  needs a token in both `DARK` and `LIGHT` — weigh against `D_color_slots`,
  which chose a per-component slot over a chrome token for `ProgressBar`, the
  counter-argument being that validity spans five-plus fields and `hint_color`
  is the precedent for a semantic non-bg token. This is also where
  the *ink* half of `D_bad_input`'s continuity ruling lands: the fact is
  correct at every instant, but showing it per keystroke flashes red through
  the act of typing correctly, so whoever paints owes a settling rule — and
  owes the measurement `ideas/bad-input.md` §3 has never taken.
- **A per-child attribute map is a solved shape, if the container wins.**
  `Box` already keeps constraints in an identity-keyed per-child map that is
  explicitly *not* a second copy of ordering (`D_box_layouts`), and
  `Component::Slot` is the tree-native answer for a swappable region
  (`D_slots`). A `FormLayout` holding `{field => caption}` copies the former.
- **Measuring captions does not reopen bottom-up sizing.** Aligning a column of
  captions needs the *container's own* strings measured, which is caller-side
  arithmetic — the same move `Select` makes when it measures its labels and
  assigns the rect it computed (`D_select`, `D_box_layouts`' "`align:` is legal
  only because the cross extent is caller-supplied"). Worth writing down
  because it looks like the banned channel and isn't.

## The `HasValidation` question, inherited whole from the bad-input work

That design shipped a field-side channel and then found it could not answer
where a **rule's verdict** lives, because the answer depends on who paints.
So the entire Vaadin-shaped `HasValidation` pair — `invalid?` and
`error_message` — is parked here, along with the ruling that keeps it off the
components meanwhile.

**Current ruling: there is no `HasValidation`, and no component carries
`invalid?` or `error_message`.** Four reasons, in the order they bite:

- **The field is not the authority.** It could neither compute a verdict nor
  recompute it after a sibling changed, so the member would be a cell with a
  second writer and no owner — the desync shape `D_tree_api` pushes back on.
  Vaadin's own custom-field guide warns against sharing the `invalid` /
  `errorMessage` properties between internal and external validation
  ("external validation is likely to override or ignore the internal state"),
  and the cleanest form of that warning is *don't put the external half on the
  component at all*.
- **Nothing reads it today.** No framework code paints a message, so an
  `error_message` on a field is a member with zero consumers — speculative API,
  which is the one thing a pre-1.0 seam should not ship.
- **`invalid?` beside `bad_input?` is unreadable.** Two predicates on one face
  and no way for a caller to know which to ask. They differ in authority,
  population, and lifetime — the authority table in `D_bad_input` has the
  detail.
- **The OR belongs where both halves are known**, which is the Binder
  (`ideas/binder.md`), not the field.

**So this file owns two decisions, not one:** who *paints* an error, and where
a rule's message is *stored*. They are the same decision in both directions:

- **Container wins** → the message lives in the container's per-child map (the
  `Box` precedent above), the field never holds one, and `HasValidation` never
  exists. A field outside a `FormLayout` then shows nothing at all.
- **Field wins** → this file is what authorizes an `invalid?` / `error_message`
  pair to appear on the component, and it owes the writer discipline that keeps
  the Binder from clobbering the field's own state — i.e. it must answer
  Vaadin's warning rather than rediscover it.

**Re-grow rule for whoever picks this up:** a component gets `invalid?` or
`error_message` only when something on the component's own face *reads* it, and
never as a mailbox for a value the field cannot compute.

## Open sub-questions, unanswered

- Does `TextField` (or `HasValue`, or `AbstractStringField`) include
  `HasCaption`? If not, what happens to caption-based tree lookup?
- Does a field paint *any* invalid ink of its own, or is invalidity entirely
  the container's ink? A field used *outside* a `FormLayout` — the common case
  in a hand-built pane today — shows nothing at all under the container-owns
  answer, which may be acceptable or may be the objection that kills it.
- One row or two? `Name: [_____]` (caption inline, left) versus a caption row
  above, versus a caption column the layout aligns. Each has a different
  answer for where an error message goes (inline right, or a third row).
- Where does a required indicator live, when it arrives? `D_has_value` parked
  it; it rides whichever answer wins here.
- Does the container need to *react* to a field's validity changing, and if so
  is that a listener per child or one notice on the layout? Note
  the deferred push notice is deliberately named for the *bad-input* channel
  only, precisely to avoid a display-driven "anything changed" notice before
  this question is settled.

## Related

`D_bad_input` (the shipped field-side channel; the population test; the
continuity ruling), `ideas/bad-input.md` (the push notice and `on_blur` this
file unblocks),
`ideas/binder.md` (the four-layer vocabulary; the consumer of what this note
would paint), `ideas/new-components.md` (infra item 2, the field label/helper
seam — what Form Layout is actually blocked on; Tier 2 Form Layout, Custom
Field),
`D_status_bar` (no framework-reserved row), `D_bg_surface` (`BG_STATES` is
closed), `D_color_slots` (component slot vs. chrome token), `D_inverse`,
`D_box_layouts` (the per-child attribute map; caller-supplied cross extent),
`D_slots`, `D_select` (caller-side measurement), `D_has_value` (the parked
required-indicator and read-only axes), AGENTS.md "Input values" (caption is
chrome, text is value; the mixin-for-lookup rule).
