# `handle_` vs `on_` — the naming rule Tuile follows but never wrote down

**Status:** brainstorm, opened 2026-09-17; **the spelling settled 2026-09-17.**
Two prefixes, not three: `handle_foo` is the override point, `on_foo=` is the
listener slot, and the hook-vs-slot collision is gone because no `on_` method
survives in `lib/`. Every `handle_` declares a Boolean claim; whether a router
consults it is a property of the dispatch mechanism, not of the name. That is
Rule C below, and it closes `Q_bare_hook_names`, `Q_accessor_discipline` and
`Q_paste_verdict`. **Visibility is the remaining open half**, and it is separable —
it survives every spelling. Pre-1.0, so backward compatibility is not a constraint;
and separating the names also dissolves the hook-first/slot-first asymmetry that
*Direction of upgrade* was written to warn about.

## Why this exists

There is no written rule for when a `Component` method is named `handle_foo` and
when it is named `on_foo`, so every new component re-decides it. The question
surfaced concretely in `mouse-event-model.md` as `Q_handler_naming` — is the new
mouse vocabulary `handle_mouse_down` or `on_mouse_down`? — and that file calls
Up/Drag "genuinely ambiguous" under the informal rule it states.

The premise of this note is that the tree already *has* a rule; it was just never
articulated, so the two places it is violated look like precedent rather than
warts.

## The inventory, measured 2026-09-17

Three families, not two — as the tree stands today. Rule C below merges the first
two, so read this as the starting position rather than the conclusion; the last
column in particular is the question Rule C rejects.

| Family | Distinct names | Who writes it | Does a caller consult the answer? |
|---|---|---|---|
| `handle_foo(event)` | 5 | subclass overrides | **yes** — Boolean claim |
| `on_foo` (hook) | 15 | subclass overrides | no — return ignored |
| `on_foo=` (slot) | 18 | app assigns a Proc | no |

**Handlers (5):** `handle_key`, `handle_mouse`, `handle_paste`,
`handle_text_input_key`, `handle_mnemonic`.

**Hooks (15):** `on_attached`, `on_detached`, `on_focus`, `on_blur`,
`on_child_removed`, `on_child_visibility_changed`, `on_width_changed`,
`on_text_mutated`, `on_caret_mutated`, `on_editor_change`, `on_half_change`,
`on_theme_changed`, `on_locale_changed`, and on `Screen` (not a `Component`)
`on_color_scheme`, `on_background_color`.

**Slots (18):** `on_change`, `on_click`, `on_close`, `on_cursor_changed`,
`on_dismiss`, `on_enter`, `on_error`, `on_error_message_change`, `on_escape`,
`on_focus_changed`, `on_item_chosen`, `on_key_down`, `on_key_up`, `on_pick`,
`on_tab_selected`, `on_value_change`, plus `on_theme_changed` and
`on_locale_changed`, which are **both** hook and slot.

One homonym is in no family at all: `VerticalScrollBar#handle_char` is *handle* the
noun — `terminology.md` defines it as the scrollbar's moving part and pointedly
declines CSS's "thumb", so the name stays and so do its siblings `handle_start`,
`handle_end` and their opposite `track_char`. It costs nothing under the tripwire
this file settles on, which greps `def on_` and never looks at `handle_`. But it is
a standing exception to Rule C's "every `handle_` declares a Boolean claim", so
anything that ever checks *that* half needs an allowlist — which is a reason not to
build that check.

**The `on_` prefix is now reserved** (2026-09-17, acted on): the three methods
that carried it as the *preposition* were renamed — `Component#on_tree` →
`#walk_tree`, `#on_shown_tree` → `#walk_shown_tree`, `EventQueue#on_loop_thread?`
→ `#in_loop_thread?`. This was separable from everything else in this file: under
every candidate spelling below, a tree walk and a thread predicate do not belong
in the event namespace, so it did not have to wait on `Q_bare_hook_names`.
`walk_` over `each_` because "walk" is already the house word in prose and
`each_*` implies an Enumerator these do not return.

## Three candidate rules, scored against the tree

**Rule A — the composition axis.** `handle_` is what you override when extending
a component; `on_` is what you assign on a stock instance (`Button.new.on_click =
-> { … }`).

Scores badly as a *prefix* rule: it is contradicted by all 13 override-only
hooks. Renaming them (`handle_attached`, `handle_theme_changed`) would be worse
than the inconsistency — "handle" promises a verdict, and there is nothing to
verdict on when a component is told it has been attached.

But Rule A is describing something real. It is simply not carried by the prefix:
it is carried by the `=`. A hook and a slot are both `on_`; the writer is what
marks the composition path.

That "renaming them would be worse" sentence is the one Rule C overturns, and it is
worth marking rather than deleting, because the rename *is* what this file settles
on. What made it acceptable was not finding something to verdict on: it was
declaring the verdict uniformly and documenting it as permanently unused wherever
no router exists.

**Rule B — the router axis.** `handle_` names a method a **router** consults:
it returns a Boolean claim, and the router uses that answer to decide where the
event goes next (bubble further, stop, try the next sibling). `on_` names a
notification the framework has already committed to — the return is ignored and
nothing can refuse it.

Scores at 3 of 5 on the handler side, and cleanly on the other 33:

- `handle_key` — bubbles up the focus chain until one returns true
  (`screen_pane.rb:324`). ✔
- `handle_text_input_key` — the answer decides fall-through to the `case` in
  `handle_key`. ✔
- `handle_mnemonic` — `MenuBar` scans cascades and stops at the claimer. ✔
- `handle_paste` — documented `@return [Boolean]`, but delivery is to
  `screen.focused` and stops (`screen_pane.rb:199`), with **no caller reading the
  answer**. The Boolean is vestigial. ✘
- `handle_mouse` — `@return [void]`, and it walks the tree as well as acting
  (`component.rb:349`). ✘

Both failures are already known warts that `mouse-event-model.md` exists to
delete — that file's opening paragraph names the `handle_mouse` one. So Rule B is
not being fitted to the code; the code is being fitted to Rule B by work already
in flight.

Read the two ✘ again, though, and neither is a fact about the method: both say
*no caller reads the answer*. That is what Rule C is about.

### Rule C — the settled rule, and why Rule B is not it

Rule B is right about what `handle_` *feels* like and wrong about where the fact
lives. "A router consults the answer" is not a property of the method; it is a
property of a caller in another file. Give `handle_paste`'s verdict a reader
tomorrow and the method must rename although nothing about it changed. A naming
rule whose input is a distant file is one nobody can apply locally.

**Rule C — `handle_foo` declares a Boolean claim: `true` means "I took this, stop
routing it". Whether anything currently routes is the dispatch mechanism's
business, documented at the mechanism.** The `=` still answers "who writes it?".

This is already how the tree is written. Measured 2026-09-17 across every override
in `lib/`: `handle_key`, `handle_paste`, `handle_text_input_key` and
`handle_mnemonic` declare `@return [Boolean]` at every site. The only `@return
[void]` is `handle_mouse` — 14 sites, all of them — and that is the family
`mouse-event-model.md` exists to replace. So Rule C costs nothing to adopt, and
Rule B's 3-of-5 score was measuring the wrong thing: both its failures are about
*callers*, not about the two methods.

Two consequences. Both must be written down or they rot.

**`handle_paste` keeps its Boolean and its name.** Nothing reads the verdict today
— delivery is to `screen.focused` and stops (`screen_pane.rb:199`) — and under
Rule C that is not a defect: it is a claim nobody has asked about yet.

**The unrouted hooks are the carve-out, and it is permanent.** For all 15 of
today's hooks the return is unused, and their rdoc must say **unused and will stay
unused** — not "not yet". For the `walk_tree` fan-outs among them it is stronger
than that: honouring the return would be *wrong*. `screen.rb:261` is
`@pane&.walk_tree { _1.__send__(:on_theme_changed) }`, which discards the block's
value by construction, and `AGENTS.md` pins plain `walk_tree` as the framework
fan-out — lifecycle, theme, locale, invalidation — that even a hidden component
gets, so a subtree "claiming" a theme change would strand its descendants
unnotified. A hopeful "yet" anywhere in this family reads as an invitation to
implement pruning and break that invariant.

### This closes `Q_handler_naming` by dissolving it

`mouse-event-model.md` proposes the vocabulary and calls Up/Drag "genuinely
ambiguous" between the two prefixes, "since nothing else can claim them". Under
Rule C there is no choice left to make: every mouse event an override *receives*
is `handle_`, and the routed/unrouted distinction moves out of the name and into
each event's rdoc.

```
handle_mouse_down        tunnels; someone claims it       verdict routed
handle_mouse_scroll      bubbles until consumed           verdict routed
handle_mouse_up          goes to the grabbed component    verdict unused
handle_mouse_drag        same                             verdict unused
handle_mouse_move        fan-out                          verdict unused
handle_mouse_enter/exit  same                             verdict unused
```

Any of those may additionally gain an `on_mouse_*=` slot, with no rename on either
side. If this note lands, `mouse-event-model.md`'s `Q_handler_naming` should be
struck and replaced with a pointer here.

## Hook and slot on one name

They do not clash — `on_foo` and `on_foo=` are distinct Ruby method names — and
the pattern already ships twice. The hook **is the slot's firing site**:

```ruby
attr_writer :on_theme_changed                     # component.rb:469
def on_theme_changed = @on_theme_changed&.call    # component.rb:769
```

Two constraints fall out, and neither is currently written down or enforced:

**The slot of a dual name is `attr_writer`, never `attr_accessor`.** The
generated reader would be named `on_foo` and would silently overwrite the hook.
Today the split is exactly right — `attr_writer` for the two dual names,
`attr_accessor` for the pure slots — and it is enforced by nothing at all.

Under Rule C this constraint disappears rather than getting enforced: with the hooks
renamed there are no dual names left, so **every slot is `attr_accessor`,
unconditionally.** That is Escape 2's "make the rule unconditional" attraction —
no case analysis, collision structurally impossible — reached from the other
direction, and without costing the three load-bearing readers it would have deleted.

### `Q_accessor_discipline` — is "remember `attr_writer`" acceptable?

**Closed: no, it is not acceptable — and Escape 1 is the answer.** Raised because
a rule you must *remember*, whose violation is silent (Ruby warns on method
redefinition only under `-W`), is a bad rule. Three escapes were considered.

**Escape 1, first rejected, then accepted: make `on_` slot-only and rename the
hooks to `handle_`.** The objection was that this relocates the two-meanings
problem somewhere with no syntactic marker — today `on_foo` and `on_foo=` are
distinguished by the `=`, whereas after the rename `handle_key` (a router reads the
verdict) and `handle_theme_changed` (unrefusable) would be "distinguished by
nothing at all".

Rule C answers it: they are not distinguished, and they must not be. Both declare a
Boolean claim; only the dispatch mechanism differs, and that belongs where the
mechanism lives rather than encoded into 15 method names. The residual —
`handle_attached` reading as refusable — is real, but is now a *documented*
return-unused instead of a silent one.

The cost is a 15-hook rename across `lib/`, `spec/`, `book/`, rdoc and `sig/`, and
that is the cheap side of the ledger: hooks are invoked by the framework and
overridden in a handful of places. Every alternative in *The spelling* below either
left the collision standing or pushed the churn onto the 434 `handle_key` call
sites in `spec/`.

**Escape 2, rejected: make the rule unconditional — slots are *always*
`attr_writer`.** Attractive (no case analysis, collision structurally
impossible), but three readers are load-bearing outside the gem:
`screen.on_error.call` (`screen_spec.rb:1463`), `f.inner.on_enter` asserted nil
(`abstract_wrapping_field_spec.rb:186`, the documented "nil `on_enter` keeps
ENTER bubbling" contract), and `item.on_click.call` read cross-object on
`MenuBar::Item` (`menu_bar.rb:568`, `cascade.rb:147`). Note 16 of the 21 firing
sites already use the ivar `@on_foo&.call`, so the readers exist for callers, not
for firing.

**The failure mode is worse than a redefinition.** The `attr_accessor` collision
is only the loud half. The quiet half: someone writes `on_foo&.call` inside the
class to fire the slot — the natural habit, since for 16 of 18 slots `on_foo` *is*
the reader for `@on_foo`. On a dual name that expression **calls the hook**, which
fires the slot, and then `&.call`s the *hook's return value*. A Ruby method
returns its last expression, so `Component#on_theme_changed` returns whatever the
app's listener returned: `nil` → harmless no-op, a `Proc` → **the listener fires
twice**, a String → `NoMethodError`. Which of the three you get depends on what
the app's lambda happens to return, so it is intermittent across apps and invisible
in the gem's own tests.

That moves this from "a rule to remember" to "a rule whose violation is
undetectable by reading the call site", which is not acceptable.

**Escape 3, accepted: stop sharing the name.** See *What other toolkits do* below —
no surveyed toolkit lets the override point and the listener slot share a name, and
`R_hook_vs_listener` has the survey. Escape 1 is *how*: of the five spellings scored
there, `handle_` is the one that separates them.

Under Rule C the tripwire collapses to a single grep, because once the rename lands
**no `on_` method may be *defined* in `lib/` at all** — every `on_foo` is a reader
generated by `attr_accessor`:

```sh
grep -rhoE "def on_[a-z_]+" lib/ --include=*.rb | grep -v '=$'   # must be empty
```

That is strictly stronger than the two-list version it replaces. It guards the
`attr_accessor` collision *and* the `on_foo&.call` half, because with no
hand-written `on_` method there is nothing for `on_foo&.call` to reach but the
reader. No allowlist, per "`nomenclature_spec.rb` is the guard and holds no
allowlist". Measured 2026-09-17 it finds 15 — exactly the hooks about to be
renamed — and must read zero once they are.

**Its home is `nomenclature_spec.rb`, not `design/verify_design_tripwires.sh`.**
That script states of itself that its set of checks is closed and that "rules about
the project's own code belong in its tests and linters, which are better at it".
This is a rule about `lib/`, and `nomenclature_spec.rb` already owns the `on_`
prefix reservation.

## What other toolkits do — `R_hook_vs_listener`

Surveyed 2026-09-17; the claims and their provenance are in
`design/research.md` under `R_hook_vs_listener`. The finding that matters here:

**No surveyed toolkit lets the override point and the listener slot share a
name.** Six were looked at; every one that offers both paths separates them
lexically. They disagree only on *which side* carries the decoration, and both
directions are attested:

- decorate the **override** — Terminal.Gui v2 / .NET (`OnKeyDown` virtual vs
  `KeyDown` event), Qt (`keyPressEvent()` vs `clicked()`), Swing
  (`processKeyEvent()` vs `addKeyListener()`)
- decorate the **slot** — Cursive (`View::on_event` vs `set_on_submit`)

So Tuile's `on_` prefix is doing a job two of those give to the override and one
gives to the slot; what none of them do is give it to both.

Two side findings:

- **Qt's stated reason for the split is not disambiguation, it is the
  inheritance/composition question** — a signal for `clicked` because subclassing
  a button per button is absurd, a virtual for `keyPressEvent` because custom
  widget behaviour is written by inheriting. That is the same reason
  `attr_writer :on_theme_changed` exists here, arrived at independently.
- **The verdict-returning handler is convergent** — Terminal.Gui's `OnKeyDown`
  returns `bool`, Cursive's `on_event` returns `EventResult`, and both sets of
  docs call it *cancelable*. Independent support for the router axis above.

### The spelling, and the four that lost

Five were scored. All five separate hook from slot, so all five satisfy the survey
finding; they differ in what they cost and in how they read. `Q_bare_hook_names`
was the blocker and (b) is where it bit.

**Chosen: `handle_theme_changed` + `on_theme_changed=`.** The .NET direction —
decorate the override — applied to every hook with no exceptions.

- **All 18 slot names survive**, including the published `label.on_theme_changed =
  …` in `book/06-theming.md`, `book/10-locale.md`, two examples and the rdoc.
- **Additivity is preserved** — a hook that later gains a slot adds
  `attr_accessor :on_foo` with no rename on either side.
- **`on_foo&.call` becomes correct rather than a trap**: `on_foo` really is the
  reader, and the quiet failure above cannot be written.
- **It reads well on all 15**, including the four that defeated every bare-name
  scheme. `handle_` is the ordinary English for reacting to an event, which is the
  whole reason the informal rule reached for it in the first place.

**(a) `fire_theme_changed`, rejected.** Renames the smaller side (2 names). But no
surveyed toolkit decorates the override with the *raiser's* verb — .NET uses `On`,
Qt a noun suffix, Swing `process` — and `fire_` names an app's reaction after what
the framework is doing to it. Worse, it **breaks the additive upgrade**: if only
dual names take `fire_`, adding a slot to an existing `on_attached` renames the
hook, so the cheap upgrade becomes a breaking one; and if *all* hooks take it,
`fire_attached` reads wrong.

**(b) bare `locale_changed()`, rejected — the front-runner, and `Q_bare_hook_names`
is what sank it.** The mirror of .NET and the Cursive direction: bare name for the
override, `on_` for the slot, which is also the JS/DOM/Android reading of `on_`. It
keeps all 18 slots and the additive upgrade — but bare hook names are fine only for
the `*_changed` / `*_mutated` / `*_removed` family (11 of 15) and poor for the other
four. `attached` sits next to the existing `attached?` predicate; `focus` and `blur`
read as imperatives (`component.focus` = "focus it", which is what `screen.focused=`
does), and `focused` would collide with `Screen#focused`. Every repair is an
exemption, and an exemption is exactly the conditional this section exists to kill.
A bare name is also ambiguous with a local variable at its own call sites.

**(c) `do_theme_changed`, rejected.** Proposed as (a) repaired: a verb with
precedent — Delphi/VCL pairs a protected `DoClick` virtual with a published
`OnClick` event property — which, unlike `fire_`, could be applied unconditionally
and so keep additivity, and which dissolves `Q_bare_hook_names` outright since
`do_attached` does not collide with `attached?`. It fails on reading, at both ends:
ungrammatical on the participles that are 11 of the 15 ("do width changed"), and
*more* imperative than the bare name on the four that `Q_bare_hook_names` is about —
`do_focus` reads harder as "focus it" than `focus` does. It degrades 11 good names
to rescue 4 bad ones.

**(d) `claim_key` + `handle_theme_changed`, rejected.** The inversion: give
`handle_` to the 15 hooks where it reads best, and move the *five* routed methods to
the verb the design docs already use for them — "a Boolean claim", "stops at the
claimer", "Tab and Shift+Tab are claimed above everything". Semantically the most
precise of the five, and it puts the marked name on the rare case. It loses on two
counts. `claim_key` reads oddly as the thing an app writes. And it inverts the churn
onto the expensive side: 434 `handle_key` sites in `spec/`, 27 in `book/` and
`examples/`, 32 rdoc mentions, plus the documented
`Testing.get(…).handle_key(Keys::ENTER)` idiom. Rule C makes it unnecessary anyway,
since the verdict no longer needs a name to carry it.

**(e) `handle_key?(event)`, rejected.** Marking the routed handlers with `?` to
cement the Boolean. Three objections, the last decisive:

- `lib/` has 48 `?` methods and not one names a command, so a mutating predicate
  would be the first — and `handle_key?` commits an edit.
- The dominant call pattern is wrong for it. Of 434 `handle_key` mentions in
  `spec/`, none reads the verdict; the answer is consumed at five sites, all inside
  the gem's routers (`screen_pane.rb:324`, `menu_bar.rb:294`, `:295`, `:519`,
  `screen.rb:988`). Discarding a predicate's answer means you called it for the side
  effect, which is what `?` promises there isn't.
- `D_key_dispatch` pins the ladder as having "no gate, predicate or mode flag
  anywhere in it", the capture phase having been deleted in 0.10.0. A method on the
  delivery rung *named* as a capability query is a standing invitation to call it as
  one, and reintroduce what that decision removed.

`?` is worth keeping on the record for one reason: it is the repair for a design
that lost. Had `handle_` kept Rule B's "a router reads this" meaning *while* also
absorbing the hooks, `?` would have been the only marker left standing. Rule C makes
the marker unnecessary instead of making it carry the weight.

**Direction of upgrade — and Rule C dissolves the asymmetry.** Under the *shared*
name, hook → hook+slot was additive (add the writer, add `@on_foo&.call` to the base
body) while slot → hook+slot was breaking, because `attr_accessor` had already
published an `on_foo` reader that the hook would have to displace. That made
*ship the hook first* a real rule.

With the names separated it is gone: a hook gaining a slot adds `attr_accessor
:on_foo` and fires it from `handle_foo`; a slot gaining a hook adds `handle_foo`
and moves the firing site into it, with the published reader untouched. **Both
directions are additive, so nothing has to ship first.** One less thing to
remember, and it is the clearest practical dividend of the split.

What does *not* dissolve is `super`. The additive direction holds only if every
override calls it, and the gem already violates that on hooks whose base body is
currently empty:

- `ProgressBar#on_attached = sync_ticker` — no `super`
- `Box#on_child_visibility_changed(_child) = relayout` — no `super`

Harmless today. The day `on_attached` grows a slot, a `ProgressBar` silently
never fires the app's listener — no raise, no warning. Only `on_theme_changed`
and `on_locale_changed` document `super` as mandatory, and those are precisely
the two that already have slots; the discipline was written reactively, after the
need appeared.

The cheap fix is to make it proactive: **a `handle_` hook's rdoc demands `super`
from day one, empty base body or not.** That is what buys the additive upgrade,
and it costs a sentence.

**Rule C adds a second discipline at the same 15 sites: a base body returns an
explicit Boolean, never the listener's value.** Today `component.rb:768` reads

```ruby
def on_theme_changed
  @on_theme_changed&.call
end
```

which returns whatever the app's lambda returned. Harmless while the return is
ignored — but once `handle_` promises a Boolean, a subclass writing
`def handle_theme_changed = super` propagates a String or a Proc into a slot the
contract says is `true`/`false`, varying per app and invisible in the gem's own
specs. That is the `on_foo&.call` trap from *`Q_accessor_discipline`* reappearing at
a new site, one layer up. So every base body fires the slot and then returns `false`
on its own line. Fifteen one-line bodies, and it belongs in the written rule with
its own check rather than in each author's head.

## Visibility — the open half

The proposal on the table is **handlers and hooks protected, slots public.** It
is not what the tree does.

Rule C collapses the first two rows into one family, so the question simplifies to
*are `handle_` methods protected?* — one question rather than two. It does not
answer it, and nothing below is invalidated by the rename: the tension is the 446
spec call sites and `D_hook_visibility`, both of which survive every spelling. This
is why the rename can ship without settling it.

Measured in `component.rb` (the `protected` keyword is at line 545):

| | Public | Protected |
|---|---|---|
| Handlers | `handle_key`, `handle_paste`, `handle_mouse` | — |
| Hooks | `on_focus` (460), `on_child_removed` (507) | `on_attached`, `on_detached`, `on_width_changed`, `on_child_visibility_changed`, `on_blur`, `on_theme_changed`, `on_locale_changed` |
| Slots | all | — |

Slots are already uniformly public. The other two rows are the question.

**Hooks are 2 public / 7 protected, and only one of the two has a reason.**
Every cross-object hook call from `Screen` goes through `__send__`
(`screen.rb:261, 296, 808, 811, 868`), which is `D_hook_visibility` — so
visibility is *free* for those and protected is the right default. `on_focus` is
public anyway despite being invoked at `screen.rb:811` via `__send__`; that looks
like drift, not design. `on_child_removed` is the real exception: it is called
directly across objects at `component.rb:997` and `slot.rb:44`
(`parent.on_child_removed(self)`), so its public visibility is load-bearing
unless those sites also move to `__send__`.

**Handlers are all public, and that is load-bearing in far more places.** Inside
the gem: `chain.first.handle_paste`, `clicked&.handle_mouse`, `c.handle_key`,
`@list.handle_key`, `field.handle_mouse`, `@cascade.handle_key`,
`@body_slot.content&.handle_key`. Outside it: **446 call sites in `spec/`**, the
documented testing idiom `Testing.get(Component::Button, …).handle_key(Keys::ENTER)`
(`testing.rb:7`), and published rdoc examples (`f.handle_key(Keys::BACKSPACE)`,
`f.handle_paste("name\nstreet\ncity")`).

So "handlers protected" is not a naming cleanup — it is a decision to make
synthetic event injection go through a seam instead of a direct call. That may
well be right, and `mouse-event-model.md`'s router makes it natural for the mouse
half, but keys have no router class today and `D_key_dispatch` treats
`view.handle_key(…)` as a legitimate host move.

### Open questions

`Q_handler_visibility` — should handlers be protected once a router owns
dispatch? The tension is the 446 spec call sites and the documented `Testing`
idiom, not the gem's own internals. Options: (a) leave handlers public and let
"the router is the only *intended* caller" be a documented convention;
(b) protected + the router calls via `__send__`, and `Testing` grows an explicit
`send_key` / `send_mouse` seam that specs migrate onto; (c) protected for the new
mouse vocabulary only, leaving `handle_key` public, and accept the split.

`Q_hook_visibility_drift` — make hooks uniformly protected? That is a two-line
change for `on_focus`, and for `on_child_removed` it means moving
`component.rb:997` and `slot.rb:44` to `__send__`. Worth it for one rule with no
exceptions, or is `on_child_removed`'s direct call a legitimate container-to-
container protocol that should stay public?

`Q_paste_verdict` — **closed by Rule C.** The question was whether `handle_paste`
should become an `on_paste`, since nothing consults its answer. Under Rule C that is
not a reason to rename: it declares a claim nobody has asked about yet. It keeps its
name, its `@return [Boolean]` and its rdoc-published example, and the
documented-behaviour change the question worried about never has to happen.

## What graduation looks like

- Rule C and the `=` rule → lines under a new *Handler naming* heading in
  `AGENTS.md` *Invariants* (~1 KB; headroom at time of writing is 4.6 KB), carrying
  the permanent fan-out carve-out and the explicit-`false` base-body rule with them.
- The roads not taken — Rule A; Rule B and why a caller-dependent rule fails; the
  five spellings, especially (b) and the `Q_bare_hook_names` exemption it needed;
  the `attr_accessor` collision; the upgrade direction → `D_handler_naming` in
  `decisions.md`.
- Delphi/VCL's `DoClick` / `OnClick` pair → a line in `R_hook_vs_listener` **if it
  verifies from a primary source**; it is recalled here, not cited, and it would be
  a seventh toolkit the survey's finding holds for.
- The rename itself: 15 hooks across `lib/`, `spec/`, `book/`, rdoc and `sig/`,
  plus the 15 base bodies growing an explicit `false`.
- `mouse-event-model.md`'s `Q_handler_naming` struck, its vocabulary fixed to the
  table above.
- The two `super`-less overrides fixed (`ProgressBar#on_attached`,
  `Box#on_child_visibility_changed`), since the proactive-`super` rule lands.
- `Q_accessor_discipline`'s single-grep check → `spec/tuile/nomenclature_spec.rb`,
  **not** `design/verify_design_tripwires.sh`, whose own preamble closes its set of
  checks and sends rules about `lib/` to the tests.
- Whatever `Q_handler_visibility` settles to → one more `AGENTS.md` line, or a
  note in `D_handler_naming` if the answer is "convention, not enforcement".
