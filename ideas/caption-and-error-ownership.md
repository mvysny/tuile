# Who owns a field's caption and its error — the field, or the layout around it?

**Status:** filed 2026-09-03, brainstormed the same day; **has a recommendation
now** (§Recommendation). Split out of `ideas/bad-input.md` so that note could
stay on the field's own report. Not yet implemented: what follows is the design
plus the facts it rests on. Graduates into `D_caption_ownership` +
`D_has_validation` (or one entry), the `HasValidation` rdoc, and a `FormLayout`
when one lands.

## The question, in one line

Does a field carry its own caption and paint its own error state, or does the
container it sits in own both?

Two shapes, both shipped by Vaadin at different times, which is what makes this
a real fork rather than a preference:

- **Vaadin 8 style — the field owns it.** `field.setCaption("Name")`,
  `field.setComponentError(...)`; the component renders its own label and its
  own error indicator. In Tuile terms: `TextField` includes `HasCaption`, and
  paints the caption and an invalid ink inside its own rect.
- **Vaadin 25 style — the container places the caption.** The form item owns
  the geometry: `formLayout.addFormItem(field, "Name")`. In Tuile terms:
  `FormLayout#add(field, caption: "Name")`, the caption is the *layout's*
  cells, and `TextField` does **not** include `HasCaption` — it paints a value
  and nothing else. **Correction to the first draft of this note:** Vaadin 25
  moved only the *caption*. `invalid` / `errorMessage` never left the field
  (`HasValidation`); the field renders both itself. So even the container-owns
  precedent does not put the error on the container.

## Recommendation

**Split "invalid" into two halves with different geometry, and the fork
dissolves.**

- **The verdict** — this field is invalid. A field *can* paint this inside the
  one row it is given: red fg on the value, no second row needed.
- **The message** — "Username is required". This needs cells the field doesn't
  own.

So: **the field holds the state, whoever has the cells renders the text by
reading it off the field. The caption goes outside the field entirely.**

### Caption: outside the component

`TextField` (and `HasValue`, and `AbstractStringField`) does **not** include
`HasCaption`. Three reasons, any one sufficient:

- A caption is chrome, and chrome the field cannot paint: it has one row, and a
  caption inside it displaces the value. So `TextField#caption` would be a
  stored string with no reader on the component's own face — the mailbox shape
  the re-grow rule below forbids. The rule discriminates correctly today:
  `Checkbox` is `HasValue` *and* `HasCaption` because it draws
  `[x] Enable logging` in its own rect; `Button` and `Window` likewise. The
  axis is "paints it", not "is a field".
- A caption can be drawn many ways (left column, row above, inline) and the
  choice is the layout's. Storing it on the field would fix a rendering the
  field never performs.
- The Binder does not need it. It binds values and writes verdicts; the caption
  is presentation.

**What happens to caption-based lookup** (the AGENTS.md mixin-for-lookup
rule): it *relocates*, it doesn't die. `HasCaption` stays on the three
painters and still passes the locator test (reachable by a tree walk, more than
one implementing class). For fields, the caption exists in the tree in the
`FormLayout`'s per-child map — held by the thing that actually knows the
caption↔field association — so a locator asks the authority:
`form.field_for(caption: "Name")`, which is what Karibu does against Vaadin 25
form items. A direct handle was a *separate* decision, and it has since been
made and shipped: `Component#id` plus `Tuile::Testing.get` (`D_component_lookup`).
It is **not** the replacement for the caption channel — an id is a test handle
the app assigns, so a locator that wants "the field captioned Name" without one
still has to ask the authority holding that association.

**A field outside any form has no caption.** That is the status quo (a
hand-built pane puts a `Label` beside the field) — declining to add a
capability, not removing one.

### Error: `HasValidation`, held by the field, written from outside

```ruby
module Component::HasValidation
  attr_reader :error_message          # StyledString | nil;  nil == valid
  def error_message=(msg)             # coerce like caption=; invalidate self; fire listeners
  def on_error_message_change(&blk)   # a container subscribes at add; the app may too
end

module Component::HasValue
  include HasValidation               # every field can be invalid
  …
end
```

**One member, no `invalid?` predicate.** `bad_input?` already sits on the
face; a second predicate beside it is the unreadable pair `D_bad_input`'s
authority table warned about. Invalid *is* `!error_message.nil?`, and a caller
that wants a flag without a message sets `""`.

**Writer discipline — the answer to Vaadin's second-writer warning.** The
field never writes its own `error_message`: it computes no verdicts, so it has
nothing to write. Its own report is `bad_input?` — derived, never stored, a
different member. That leaves exactly one writer, whoever validates, and the
discipline is one sentence: **whoever sets it, sets-or-clears it on every
validate pass.** The login form:

```ruby
login.on_click do
  username.error_message = username.empty? ? "Required" : nil
  password.error_message = password.empty? ? "Required" : nil
  next if [username, password].any?(&:error_message)
  authenticate(username.value, password.value)
end
```

No layout in sight; identical inside a `FormLayout`, a `Vertical` or a
`Popup`. The Binder (`ideas/binder.md`) does the same set-or-clear loop for the
app, and ORs `bad_input?` into its verdict *before* running rules — which is
where `D_bad_input` said the OR belongs.

**Why a separate mixin, included by `HasValue`, rather than members on
`HasValue` directly:**

- Different authorities. `HasValue` is the field's *own* state; `error_message`
  is a verdict written from outside. `D_has_value` keeps that seam deliberately
  thin and self-owned; a foreign-written member sits better behind its own
  name.
- Lookup. A Binder or a test locator iterating "everything that can carry a
  verdict" walks `is_a?(HasValidation)` — reachable, more than one class, the
  same test `HasCaption` passes.
- A component that can be invalid without being a field — a composite custom
  field, a form section — includes it alone.
- It is Vaadin's split, so the Binder port reads familiar. Cost is ~12 lines.

### The field's own ink

The face reads `error_message` and paints the value in `theme.error_color` —
a semantic non-bg token in both `DARK` and `LIGHT`, `hint_color` being the
precedent. This is where `D_color_slots` gets re-weighed: it chose a
per-component slot over a chrome token for `ProgressBar`, and loses here
because validity spans every `HasValue` field.

It is **fg, not bg**, so the `R_invalid_ink_is_not_a_background` worry —
`invalid` and `focused` co-occur, a bg accent would need a 2×2 precedence
ruling — never arises. `BG_STATES` stays closed (`D_bg_surface`).

Whether the face *also* paints ink for `bad_input?` (ORing the two) is
deferred: that half inherits the settling debt from `ideas/bad-input.md` §3
(the fact flashes per keystroke). `error_message` ink has no such debt — it is
discrete, asserted at a click or a binder pass — so it ships first.

### The message: the container's cells, read off the field

`FormLayout` reads `child.error_message` and paints it in *its own* cells.
The TUI-natural placement is **inline right** —

```
Username: [________________] Required
Password: [________________] Required
```

— one row, no growth, nothing bottom-up. The message is bounded by the row;
the layout truncates with an ellipsis (`InfoWindow#lines=` is the model). A
form-level status row showing the first error is the app's to build from the
same data, not the layout's.

Because those are the layout's cells, invalidating the field alone doesn't
repaint them; the layout subscribes to `on_error_message_change` at `add`
(and unsubscribes at `remove`). **This does not contradict `D_bad_input`'s
"deliberately no push notice".** That ruling was about a *continuous* fact
that would fire per keystroke and owes a settling rule. `error_message` is
*discrete* — the app asserts it — so the notice is plain listener inversion
(data flows up via a listener the container subscribes to; the field emits
blind and stays layout-independent).

**A field outside any form** shows red ink and no text. A strict improvement
on today: the "do it yourself" option — the app owns a `Label` and writes the
same `error_message` into it — stays fully available and now gets the field's
ink for free.

### Why the two halves get opposite answers from the same rule

Worth writing down at graduation, because it looks inconsistent and isn't. The
re-grow rule is: *a component gets a member only when something on its own
face reads it.* A field can render invalidity inside its rect without
displacing the value (ink is a restyle of cells it already paints), so
`error_message` has an on-face reader. It cannot render a caption inside its
rect without displacing the value, so `caption` has none. Same rule, opposite
verdicts, for a reason — not "fields own nothing".

## Facts the recommendation rests on, so they don't get re-derived

- **`HasCaption` exists and is a mixin**, and today a caption is *chrome the
  widget paints inside itself* — a `Window` title, a `Button` label, a
  `Checkbox` label. The question was never "does Tuile have captions" but "may
  a caption be a label that sits *outside* the captioned component?" — answered
  above: yes, and then it is not the component's.
- **The caption/value line is already drawn:** `caption` is app-authored
  chrome, `text` is the user-editable value, and a component may carry both
  (AGENTS.md, "Input values"). Nothing here reopens that.
- **Top-down layout is the heaviest prior.** A field is handed one row by its
  parent and cannot grow a second one for a caption or a message; advertising a
  wanted height is the deleted bottom-up channel. `D_status_bar` says the same
  from the other side: the framework reserves no row it wasn't asked for. The
  recommendation obeys it in both halves — the ink fits the row the field has,
  the message goes in cells the layout already owns.
- **The field-side report has shipped.** `Component::HasBadInput`
  (`D_bad_input`) reports one derived fact — `bad_input_message`, on the fields
  whose input can outrun their value — and paints nothing. It is the *other*
  channel, with the *other* authority, and its existence is what makes a
  single-writer `error_message` possible. The push notice it withheld stays
  withheld; it is not the notice this note adds.
- **The message is a stored value, `bad_input_message` is derived.** Keep that
  asymmetry: a consumer must get the current `bad_input?` whichever notice woke
  it, so it is computed on read; `error_message` is whatever the last writer
  set, and *that* is the point of it.
- **A per-child attribute map is a solved shape.** `Box` keeps constraints in
  an identity-keyed per-child map that is explicitly *not* a second copy of
  ordering (`D_box_layouts`); a `FormLayout` holding `{field => caption}`
  copies it. `Component::Slot` is the tree-native answer for a swappable
  region (`D_slots`).
- **Measuring captions does not reopen bottom-up sizing.** Aligning a caption
  column needs the *container's own* strings measured — caller-side arithmetic,
  the same move `Select` makes when it measures its labels and assigns the rect
  (`D_select`; `D_box_layouts`' "`align:` is legal only because the cross
  extent is caller-supplied"). It looks like the banned channel and isn't.
- **The re-grow rule that governs both halves:** a component gets `caption` or
  `error_message` only when something on the component's own face *reads* it,
  and never as a mailbox for a value the component cannot compute or paint.

## Still open

- **`FormLayout`'s caption geometry** — caption column left (aligned, measured
  caller-side) versus a row above. Inline-left is the natural pair to the
  inline-right message; the row-above shape would want the message on a third
  row and reopens the growth question. Decide with the `FormLayout` design
  (`ideas/new-components.md`, Tier 2).
- **Required indicator.** It is chrome, like the caption, so it rides the
  container: `FormLayout#add(field, caption:, required: true)` paints the
  marker beside the caption. `D_has_value` parked it; this is where it lands
  unless a reason appears for the field to know it is required.
- **`Component#id`** — *shipped* (`D_component_lookup`), as a `Symbol` tag with
  `Tuile::Testing.get` over it. Cheap and honest: identification *is* its
  purpose, so inertness is not a mailbox smell. It was never needed to answer
  this note, and it does not settle the caption↔field question above.
- **`bad_input?` ink on the face**, ORed with `error_message` — waits on the
  settling measurement `ideas/bad-input.md` §3 has never taken.
- **`error_message=` on a *detached* field** must not raise (the login form is
  assembled before mount, and `Component#invalidate` already no-ops when
  detached) — same shape as every other setter; note it in the rdoc.

## Related

`D_bad_input` (the shipped field-side channel; the population test; the
continuity ruling; the authority table), `ideas/bad-input.md` (the push notice
and `on_blur` this note now unblocks — the settling rule is still theirs),
`ideas/binder.md` (the four-layer vocabulary; the writer of `error_message`),
`ideas/new-components.md` (infra item 2, the field label/helper seam — what
Form Layout is actually blocked on; Tier 2 Form Layout, Custom Field),
`D_status_bar` (no framework-reserved row), `D_bg_surface` (`BG_STATES` is
closed), `D_color_slots` (component slot vs. chrome token — re-weighed above),
`D_inverse`, `D_box_layouts` (the per-child attribute map; caller-supplied
cross extent), `D_slots`, `D_select` (caller-side measurement), `D_has_value`
(the parked required-indicator and read-only axes; the thin seam
`HasValidation` sits behind), AGENTS.md "Input values" (caption is chrome,
text is value; the mixin-for-lookup rule).
