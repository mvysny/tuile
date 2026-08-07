# Box layouts — `Layout::Vertical` + `Layout::Horizontal`

**Status:** designed 2026-08-07, not implemented. Not a new idea — book ch3
already sanctioned the shape and wrote down the acceptance criterion; this
file records that the criterion is now *met*, plus the design settled in
discussion and refined by a Vaadin 8 / Swing / JavaFX naming pass.

## Why now: ch3's own criterion is satisfied

`book/03-layout.md` (end of chapter) pre-approved this:

> …wishing for a `Layout.vertical([Length(3), Fill(1), …])` convenience —
> that's a known, **deliberately deferred** addition. It would be pure sugar:
> a rect producer running a small greedy 1-D pass and feeding results to the
> very same `rect=` setter you already use, with no change to the foundation.
> Absolute-first is the base; a descriptive split layer is an optional
> convenience on top, **added if and when the convenience pays for itself.**

It has paid for itself, and the evidence is our own showcase.
`examples/sampler.rb` carries **59 `Rect.new` sites**, and the dominant shape
is not the interesting two-pane split — it's a vertical stack of fixed-height
widgets with hand-accumulated y-offsets. Three tells, all over that file:

- **Cumulative magic offsets.** `inner.top + 1`, `+ 4`, `+ 6`, `+ 8`, `+ 10`,
  `+ 12` (the password demo, `sampler.rb:254-259`). Change the prompt from 4
  rows to 5 and you renumber every line below it by hand. `sampler.rb:403`
  gives up and accumulates explicitly: `inner.top + 6 + boxes.size`.
- **Hand-rolled expansion.** `[inner.height - 8, 2].max` (`:691`), same idiom
  at `:173`, `:317`, `:349`, `:571`.
- **Hand-rolled cross-axis clamp.** `[inner.width, 30].min` (`:191`, `:210`,
  `:229`, and `width =` in the password demo).

The cost isn't that hand-rolling is impossible — it's that the code a
newcomer reads to *learn Tuile* demonstrates the tedious version.

**Scoping counterweight, worth keeping honest:** `examples/file_commander.rb`
is a real app with a genuine two-pane split and needs **3** `Rect.new`; `lib/`
needs essentially none. So box layouts are **a convenience for form-shaped
content, not infrastructure the framework lacks.** Absolute stays the base.

## The hard boundary: no `Auto`, ever

v0.9.0 deleted the bottom-up `content_size` channel and `Sizing` — shipped,
then thrown away. AGENTS.md's re-grow rule allows measurement back only as an
*optional, read-only, caller-side query*, never a channel the framework
consults. That draws a clean line through every constraint vocabulary in the
wild:

| Allowed (parent-side arithmetic) | Forbidden (asks the child) |
|---|---|
| `Fixed(n)`, `Percent(n)`, `Expand(weight)` | `Auto` / `Pack` / shrink-to-fit / `PREFERRED_SIZE` |

urwid's `PACK`, CSS `auto`, FTXUI's non-`flex` default, Swing's
`GroupLayout.PREFERRED_SIZE` and ratatui's content-derived sizing all sit on
the wrong side. **This single omission is what keeps the feature sugar rather
than a reopened wound.**

It also resolves the alignment worry that nearly derailed the design.
`left/center/right` *feels* like it needs the child's width → `content_size` →
hard no. It doesn't:

> **Alignment needs *a* width, not *the child's* width.** Once the cross
> extent comes from a constraint the *caller* supplied, there is nothing to
> measure and `align:` is legal.

So no `Left { |avail| … }` block form. It's technically permitted by the
re-grow rule (caller-side measurement) but no case we have needs it, it's
un-inspectable and awkward to spec, and anyone who genuinely needs a computed
cross width still has `Absolute` + a `rect=` override. Keep the escape hatch
where it already is.

## Decisions settled

1. **Default main-axis constraint: `Fixed(1)`.** Matches Vaadin 8's
   bump-everything-to-the-top default, and forms are the use case — almost
   every field is one row tall. (Rejected `Expand(1)`: "bare `Vertical` evenly
   splits its rows" is tidier as a container story but wrong for what people
   will actually build.)
2. **Default cross-axis constraint: `Percent(100)`**, and **`Expand` is
   main-axis-only — passing it as `cross:` raises.** The cross axis has
   exactly one child per row, so there is no competition; a weight is
   meaningful only against sibling weights. `Expand(1)` as the cross default
   would advertise a negotiation that cannot happen, and leaves "what does
   `Expand(2)` mean on the cross axis?" merely undocumented instead of
   unaskable. `Percent(100)` says exactly what happens and is exact (no
   rounding).
3. **`spacing` and `padding` are layout-global, not per-child.** Beyond
   simplicity: *a gap between two items is a property of the sequence, not of
   either child*, so per-child spacing has an unresolvable ownership question
   — does child N own the gap after it, or child N+1 the gap before it? Both
   conventions exist in the wild and both confuse. (Swing's
   `GridBagConstraints.ipadx`/`ipady` is the per-child version; see the
   toolkit pass for why that family is a warning, not a model.)
4. **Percent *and* Expand resolve against space that is actually available** —
   extent minus main-axis padding minus `spacing * (n - 1)`. Otherwise two
   `Percent(50)` children overflow.
5. **`Fixed`, not ch3's `Length`.** `Length` names a unit; `Fixed` names a
   policy, which is what these are.
6. **Remainder from weighted `Expand`: distributed one cell at a time,
   leftmost-first.** Decided here (no prior preference). Reasoning and
   rejected alternatives below.
7. **`Expand(weight)`, not `Fill(weight)`.** Settled by the toolkit pass —
   the reasoning is strong enough to be the headline naming decision, so it
   lives in its own section below.
8. **`Layout::Box` is public**, and is both the shared 1-D pass and the home
   for the common calculation helpers (available-extent arithmetic, weighted
   remainder distribution, cross-axis placement), so a future third
   box-shaped layout extends it rather than re-deriving them.

### Why `Expand`, not `Fill`

`Fill` is the wrong word, and three independent toolkits say so — because
**"claim the leftover space" and "stretch into the space you were given" are
two different concepts**, and every mature toolkit that models both calls the
second one *fill*:

- **GTK** `pack_start(child, expand, fill, padding)` — two separate booleans,
  and `fill` only has any effect when `expand` is already true. `expand` =
  allocate extra space to this widget; `fill` = does the widget *grow into*
  that space, or does it become padding *around* the widget.
- **Swing** `GridBagConstraints` splits the same pair as `weightx` (distribute
  extra space to the cell) and `fill` (stretch the component within its cell).
- **JavaFX** splits it as `HBox.setHgrow(node, Priority)` and the container's
  `fillHeight` property.
- **Vaadin 8** names only the first one, and calls it **`setExpandRatio`**.

So across the ecosystem, *fill* means cross-axis stretch — which in Tuile is
exactly what `Percent(100)` already does by default. Naming our main-axis
slack-claiming constraint `Fill` would use the industry's word for the one
thing it isn't, right next to the feature it actually describes. `Expand`
takes Vaadin 8's name, says "grow to take slack" without claiming anything
about stretch, and leaves `Fill` permanently free so it can never be
introduced later as a confusing near-synonym.

(ratatui does call it `Fill` and CSS calls it `flex-grow`. Neither models the
stretch concept separately, so neither had the collision to avoid.)

### Why leftmost-first for the remainder

Naive "last `Expand` absorbs everything left over" is tempting — it matches
the hand-written idiom in ch3 and `Sampler#rect=` (`left_w`, then
`rect.width - left_w`), and guarantees an exact sum structurally. **But it
degrades badly with more than two children:** five equal `Expand`s in 12 rows
gives floors of 2 each (10 used) and dumps 4 on the last one — a visible 2×
discrepancy, which is exactly the "one cell off is plainly visible on a
character grid" failure ch3 warns about, amplified.

One-cell-at-a-time leftmost-first gives `3,3,2,2,2` instead: max error 0.6
cells, exact sum still structural (`base * n + remainder == total` by
construction), and auditable in a sentence — *"remainder cells go to the
earliest `Expand` children, one each."*

Rejected alternatives:

- **Last-absorbs-all:** the 2× defect above.
- **Trailing-first one-at-a-time** (`2,2,2,3,3`): same fairness *and* matches
  ch3's remainder-to-the-right idiom for the two-child case. Genuinely close
  — rejected because leftmost-first is the ecosystem convention (CSS
  `flex-grow`, ratatui `Fill`, urwid `weight`), so a user coming from anywhere
  else guesses it right, and favoring the front reads as "primary content gets
  priority" rather than "ran out of space."
- **Largest-remainder / Hare quota:** fairest, least auditable. Reverse-
  engineering which child got the extra cell is precisely the solver opacity
  ch3 rejects.
- **Priority tiers instead of weights** (JavaFX `Priority.ALWAYS / SOMETIMES /
  NEVER`): sidesteps remainder arithmetic entirely — no weighted division, so
  no remainder to distribute. Rejected because it can't express a 1:2 split,
  which is the common case a sidebar wants; Vaadin 8's ratio and CSS
  `flex-grow` both chose weights over tiers.

**Known wart to document, not hide:** for the two-child case the layout gives
the extra cell to the *left/top* child while ch3's hand-written example gives
it to the *right*. Different mechanisms, no shared code — conflating them
would be over-fitting — but ch3 should acknowledge it in a clause.

## API

```ruby
class PasswordDemo < Tuile::Component::Layout::Vertical
  def initialize
    super(spacing: 1, padding: Insets[top: 1])
    add(prompt,   Fixed(4))
    add(user,     Fixed(1), cross: Fixed(30))
    add(password, Fixed(1), cross: Fixed(30))
    add(reveal,   Fixed(1))
    add(status,   Fixed(1))
  end
end
```

That replaces `sampler.rb:254-259` — five `Rect.new` calls carrying six
hand-computed offsets plus the `[inner.width, 30].min` clamp.

**Signature:** `add(child, main = Fixed(1), cross: Percent(100), align: :start)`.
The existing `Layout#add(Component | Enumerable)` contract is preserved; for
the Enumerable path the same constraint applies to every element, which makes
`add([a, b, c], Fixed(1))` genuinely useful.

**`align:` is `:start | :center | :end`**, deliberately axis-agnostic.
`Vertical`'s cross axis is horizontal and `Horizontal`'s is vertical, so
`:left/:right` + `:top/:bottom` would mean two vocabularies for one concept.
Each class's rdoc says which edge `:start` is. `align` is a no-op at the
default `Percent(100)`.

**Constraints are stored in a `compare_by_identity` Hash keyed by child**,
cleaned up in `Layout#remove`. Against AGENTS.md's slot-desync rule: this is a
*per-child attribute map, not a second copy of ordering* — `@children` remains
the sole ordering authority — so it doesn't trip the rule the way
`ScreenPane#popups` does.

**`Layout.vertical([[prompt, Fixed(4)], …])`** stays available as ch3 promised,
but only as a convenience constructor looping over `add`. Not the primitive:
rebuilding the whole list to add one child is bad for dynamic UIs.

### Rejected: a constraint attribute on `Component`

`child.layout_constraint = Expand(1)` is the tempting third option and is a
**hard reject** — it's `content_size` wearing a hat. Even though the parent
still does the arithmetic, putting the field on `Component` re-establishes
"the child declares its size wish", and every non-layout parent would have to
ignore it. The constraint belongs to the **parent–child relationship**, which
is exactly why it lives at the `add` call site.

**JavaFX is this option in production, and confirms the downside.**
`HBox.setHgrow(node, Priority.ALWAYS)` stores the constraint *on the child
node*; the existence of `HBox.clearConstraints(node)` is the proof. Two
documented consequences: you must remember which container class's static
setter applies, and **a node reparented into a different container silently
keeps its stale constraints.** Exactly the failure mode predicted above, now
with a citation.

### The nice ergonomic (verified)

Bare `Fixed[4]` / `Expand[1]` **resolve inside a user's `Layout::Vertical`
subclass with no prefix and no `include`** — Ruby's constant lookup walks the
ancestors of the enclosing class, and `Layout` is one. Confirmed with a
scratch script. So nesting the constraints under `Layout` costs the user
nothing in verbosity, which removes the only argument for a top-level
`Tuile::Fixed`.

### Files (Zeitwerk)

Precedent already exists — `component.rb` + `component/` is the same pattern,
so a directory namespace under `layout.rb` works identically:

```
lib/tuile/component/layout.rb              + nested Fixed / Percent / Expand / Insets
lib/tuile/component/layout/box.rb          Layout::Box — shared 1-D pass + calc helpers
lib/tuile/component/layout/vertical.rb     Layout::Vertical
lib/tuile/component/layout/horizontal.rb   Layout::Horizontal
```

The constraints are tiny value types (`Data.define`, like `Fraction`) bound
tightly to `Layout`, so they stay in `layout.rb` alongside the existing
`Layout::Absolute` — same call as `List::Cursor`/`None`/`Limited` living in
`list.rb`.

**On `Box` as a shared base, vs. the COP duplicate-don't-DRY rule
(`D-float-field`):** that rule targets *shallow* commonality. This isn't —
the greedy pass is substantial and byte-for-byte identical except for which
of `(left, top)` / `(width, height)` it reads. `Box` parameterizes it behind
two private hooks (`main_extent(rect)`, `build_rect(...)`) and `Vertical` /
`Horizontal` are ~10-line concrete subclasses. That is the sanctioned
*cohesive component base* (`AbstractMasterDetail`), not an `AbstractView`
junk drawer. `Box` stays abstract as a *class* — no `axis:` parameter, because
`Vertical`/`Horizontal` is what everyone actually writes.

## The algorithm

Main axis, in order:

1. `available = main_extent - main_padding_both_edges - spacing * (n - 1)`
2. `Fixed(n)` children take `n`, clamped to what's left.
3. `Percent(p)` children take `(available * p / 100.0).round` — `.round` for
   consistency with `Fraction#resolve`.
4. `Expand(w)` children split the residue by weight; remainder one cell at a
   time, leftmost-first.
5. Positions accumulate from the start edge, `spacing` between.

Cross axis, per child: `cross_available = cross_extent - cross_padding`, then
`Fixed` (clamped) or `Percent`, then `align` positions within the leftover.

## Edge cases to nail down in specs

- **Over-subscription** (Fixed + Percent exceed available): first-come-first-
  served in declaration order; starved children get a **zero-extent rect**.
  No error, no solver. Already a well-defined state — `Rect#empty?` covers 0
  *and* negative, and ch3 documents that a width-0 child paints nothing.
- **No `Expand` present:** slack is left at the end (pack from start). This is
  why we need no Swing-style glue — and it matches what the sampler does now.
- **`padding` exceeds the extent:** everything gets a zero rect.
- **`Expand(0)` or negative weight:** raise at declaration. A silent
  zero-extent child is a miserable debugging experience.
- **`relayout` must no-op while `rect.empty?`** — `add` runs during
  `initialize`, before any rect is assigned. `sampler.rb`'s `Panel` already
  guards exactly this way (`unless rect.empty?`).
- **Every child-list mutation relayouts *and* invalidates — `add` and `remove`
  both, unconditionally** (plus `spacing=` / `padding=`). Today
  `Layout#remove` only invalidates when the layout goes *empty*, which is
  correct for `Absolute` (siblings don't move) and wrong for a box: removing
  any child shifts every child after it, so `Box` overrides `remove` rather
  than inheriting the empty-only guard. Same for `add`, which shrinks
  everyone's share.
- **Thread confinement comes for free — do *not* add `screen.check_locked`.**
  `Screen#invalidate` calls it (`screen.rb:271`) and `Component#invalidate`
  reaches it whenever the component is attached, so every mutator ending in an
  `invalidate` — `add`, `remove`, `spacing=`, `padding=`, `rect=` — already
  raises off-thread. Verified: all three raise `Tuile::Error: UI not owned by …`
  from a spawned thread. That same early return when *detached* is what lets a
  tree be assembled with no `Screen` in the process.
  Two corrections to earlier notes in this file, since both misread the
  codebase: `check_locked` has no dependency on `Screen.instance` (it's a plain
  instance method — the dependency is `Component#screen`); and there is no
  "content setters are guarded, geometry isn't" convention. Only **9**
  component-level call sites exist in the whole gem (`List#add_lines` and
  TextView's 8 incremental mutators), and they are fail-fast exceptions for
  methods that do substantial work *before* reaching `invalidate`.
  `List#lines=` is unguarded.
- **Nesting is the answer to non-uniform gaps** — see below. Spec it, because
  it's load-bearing for decision 3.

### Nesting, and why it removes the need for per-child spacing

The progress-bar demo (`sampler.rb:619-624`) looks like a counter-example to
global spacing:

```
prompt  +1  h4
bar     +6      gap 1
status  +7      gap 0   ← group
spinner +9      gap 1
caption +10     gap 0   ← group
```

It isn't non-uniform spacing — it's **two groups of two**. A
`Vertical(spacing: 0)` nested in a `Vertical(spacing: 1)` expresses that
directly; per-child spacing would let you *fake* the grouping without
expressing it. Boxes within boxes, and the same answer FTXUI and CSS give.

### What `Horizontal` doesn't buy us

`sampler.rb:79-82` becomes `add(@left_window, Fixed(30))` +
`add(@right_window, Expand(1))` — but that **loses**
`(rect.width / 3).clamp(20, 40)`, which is a `Min` + `Max` around a `Percent`
and unsayable in a three-constraint vocabulary. Fine: that's a one-line
`Absolute` override, and it's better than adding `Min`/`Max` on day one. But
it is honest evidence that `Horizontal` serves *forms* better than it serves
*app shells*.

## Toolkit pass: Vaadin 8 / Swing / JavaFX (2026-08-07)

Beyond the `Expand` rename above, four things worth keeping.

### JavaFX independently arrived at both our defaults

`VBox.fillWidth` defaults to **true** (children stretch across the cross axis)
and `VBox` alignment defaults to **`Pos.TOP_LEFT`** with `spacing = 0` (pack
from the start, slack at the end). Those are decisions 2 and 1 respectively,
reached independently by a mature toolkit. Good confidence signal on the two
defaults we had the least evidence for.

### `Insets`: keep the type, keyword-only — the trap is sharper than expected

Both Swing and JavaFX have an `Insets` value type, which validates the name
and the concept. But their constructors disagree on **order**:

- `java.awt.Insets(top, left, bottom, right)`
- `javafx.geometry.Insets(top, right, bottom, left)` — CSS order

Same class name, same four numbers, silently different meaning: a live
migration bug between two toolkits *in the same language*. So `Layout::Insets`
is **keyword-only — no positional four-arg form** (`Data.define` gives us
keyword init for free), plus an Integer coercion for the uniform case. That
resolves the open question on the `Insets` shape.

### `padding`, not Vaadin's `margin`

Vaadin 8 calls the container's own inset `setMargin`; CSS, Swing (`Insets` +
`setBorder`) and JavaFX (`setPadding`) all call it padding. Three to one — and
decisively, in CSS `margin` means the space *outside* the box, so borrowing
Vaadin's word for an inset would be actively misleading.

### `GridBagConstraints` is the creep endpoint — 11 fields

`gridx`, `gridy`, `gridwidth`, `gridheight`, `weightx`, `weighty`, `anchor`,
`fill`, `insets`, `ipadx`, `ipady` — and it is the layout manager everyone
agrees is hardest to learn. Our tuple is **3** (main, cross, align) plus two
container-globals. Worth keeping as the explicit tripwire: `ipadx`/`ipady` is
the per-child padding we rejected in decision 3, and `insets` per-child is the
per-child spacing we rejected in the same breath. If our tuple starts growing
toward four or five, this is what it's growing into.

### Deliberately not borrowed

- **Baseline alignment** (Swing's `anchor` has `BASELINE`,
  `ABOVE_BASELINE_LEADING`, …): a text-*rendering* concept. On a character
  grid every row shares one baseline, so it's meaningless.
- **`BorderLayout` / `BorderPane` / Textual's `dock:`**: nesting
  `Vertical(Fixed, Expand, Fixed)` covers it, and `ScreenPane` (content +
  status bar) already *is* one hard-coded.
- **Swing `GroupLayout`** (`SequentialGroup` / `ParallelGroup` /
  `addGap(min, pref, max)`): machine-generated by NetBeans Matisse for a
  reason, and its min/pref/max gaps are precisely the deleted channel.
- **`CssLayout` / `AbsoluteLayout`**: we have `Absolute`.
- **Swing glue** (`Box.createVerticalGlue`, `createRigidArea`,
  `createHorizontalStrut`): invisible filler *components*. These exist because
  `BoxLayout` has no per-child weight and doesn't pack from the start. Our
  pack-from-start + `Expand` needs none — and the Tuile equivalent, a `Gap(n)`
  spec entry with no child, is unnecessary because nesting handles grouped
  gaps.

### Forward note: the vocabulary generalizes to a grid

JavaFX `GridPane` takes `ColumnConstraints(percentWidth, hgrow)` /
`RowConstraints` — i.e. **the same three-constraint vocabulary, applied per
row and per column.** That's a good sign the vocabulary is right, and it's the
natural path to the Form Layout that `ideas/new-components.md` Tier 2 wants
(currently blocked on a field label/helper seam, not on layout). If a
`Layout::Grid` ever lands it should reuse `Fixed`/`Percent`/`Expand` verbatim
rather than inventing a second set.

## Still open

- ~~`Insets` shape~~ — settled by the toolkit pass: keyword-only, Integer
  coercion for uniform.
- ~~Does `Percent` on the cross axis pull its weight?~~ **Keep it.** JavaFX
  `GridPane`'s `percentWidth` and Vaadin 8's `setWidth("50%")` are real
  precedent for percentage cross sizing.
- ~~Whether `Layout::Box` should be public API~~ — settled: public, and the
  home for the shared calculation helpers.

Nothing blocking left; this is implementable as written.

## On graduation

Per AGENTS.md's pipeline — user-facing half → book, invariants → AGENTS.md,
the choice + roads-not-taken → DECISIONS.md. Concretely:

- **book ch3:** rewrite the deferral paragraph into a real section
  (`Length` → `Fixed`, `Fill` → `Expand`, the two-child remainder clause, the
  nesting-for-groups idiom), and tighten the "validated by the ecosystem"
  sentence per the survey below.
- **AGENTS.md:** the no-`Auto` invariant; "alignment needs a width, not the
  child's width"; `Expand` is main-axis-only; the constraint map is an
  attribute map and not an ordering copy; relayout no-ops while `rect.empty?`;
  `Box` overrides `remove` because siblings shift.
  **Also sharpen the threading section while there.** It reads "most UI methods
  call `screen.check_locked`, which raises otherwise" — true only if "call" means
  *reach transitively*. Directly, components almost never call it (9 sites in the
  gem); enforcement rides `Component#invalidate` → `Screen#invalidate`. Worth
  stating outright, because the current wording invites adding redundant explicit
  guards to every new component.
- **DECISIONS.md `D-box-layouts`:** decisions 1-8 with their rejected
  alternatives — especially the `Expand`-vs-`Fill` naming argument, the
  remainder-distribution four-way, the constraint-on-`Component` reject (with
  the JavaFX evidence), and the block-form-alignment reject.
- **`ideas/new-components.md`:** tick the Box-layouts row and drop it from the
  gating-infrastructure list. Its current wording — "biggest **structural**
  win" — is wrong either way and should read *additive*: ch3's whole point is
  that this changes no foundation.
- Then delete this file.

## Ecosystem survey (2026-08-07) — keep, it's the roads-not-taken evidence

| Tier | Frameworks |
|---|---|
| **Nothing** | ncurses (windows + coordinates); Bubble Tea (layout = string joining via lipgloss `JoinVertical`/`JoinHorizontal`; third-party `stickers` bolts on flexbox because users wanted it) |
| **Simple 1-D boxes** | FTXUI `hbox`/`vbox`/`gridbox` + `flex`; brick `hBox`/`vBox`; urwid `Columns`/`Pile` with GIVEN/WEIGHT/PACK; tview `Flex` + `Grid` |
| **Constraint solver** | ratatui — `Length`/`Percentage`/`Ratio`/`Min`/`Max`/`Fill` fed to a real **Cassowary** solver (kasuari) |
| **Full CSS / flexbox** | Textual (CSS: vertical/horizontal/grid/**dock**); Ink (embeds **Yoga**, Facebook's actual flexbox engine — the one React Native uses) |

**The insight that decides our tier isn't "TUI ⇒ simple" — it's *who owns the
coordinates*.**

- Ink and Textual are *retained-mode declarative*: the author writes a tree and
  never sees a rect, so they **must** ship a full engine — there's no escape
  hatch.
- ratatui is immediate-mode, but `Layout::split` is the *only* way to obtain a
  `Rect`, so its constraint vocabulary is load-bearing rather than optional.
  Also why constraint-resolution surprises are a recurring complaint there —
  ch3's "solver non-determinism is *visible* on a character grid", observed in
  the wild.
- Tuile, ncurses and Bubble Tea hand the author coordinates. **Once `rect=`
  exists, a layout is strictly optional sugar** — declinable per component,
  which none of the top tier can offer.

**Correction owed to ch3.** It claims "enough is validated by the ecosystem"
citing tmux/neovim/k9s/lazygit/htop. True of *app architecture*, but not of
*framework feature sets*: the two most-adopted modern TUI frameworks shipped
full CSS/flexbox and the flagship Rust one ships a Cassowary solver. The
argument survives intact — ch3 argues against a *solver*, not against
*convenience layouts* — but that sentence needs tightening, because it's our
public case.

### Bonus: Vaadin 8's #1 layout confusion validates the no-`Auto` boundary

The classic Vaadin 8 support question is *"`setExpandRatio` does nothing"*, and
the answer is always that the child also needs `setSizeFull()` / `100%` — an
expand ratio alone is inert. That bug exists **because a Vaadin 8 component has
both its own size and an expand ratio: two size channels that have to agree.**

Tuile cannot have that bug, because there is no component-side size to
disagree with the constraint. The single most common confusion in the toolkit
we're borrowing the `Expand` name from is a direct consequence of the channel
v0.9.0 deleted — worth a sentence in `D-box-layouts`, because it's the
strongest available argument that the deletion was right.
