# `handle_` vs `on_` — the naming rule Tuile follows but never wrote down

**Status:** brainstorm, opened 2026-09-17. The `handle_` / `on_` split is close to
settled. The **hook-vs-slot name collision is the live question** — surveying six
toolkits (`R_hook_vs_listener`) showed none of them shares a name between the two,
so the answer is to stop sharing it; which spelling wins is open, and
`Q_bare_hook_names` is the blocker. Visibility is separately open. Pre-1.0, so
backward compatibility is not a constraint — but see *Direction of upgrade*, where
one direction is free and the other is not, which matters even pre-1.0 because it
decides what to ship first.

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

Three families, not two.

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

One homonym is not in any family and must be exempted explicitly, or a grep for
the rule trips on it: `VerticalScrollBar#handle_char` is *handle* the noun — the
scrollbar thumb, per `terminology.md`.

**The `on_` prefix is now reserved** (2026-09-17, acted on): the three methods
that carried it as the *preposition* were renamed — `Component#on_tree` →
`#walk_tree`, `#on_shown_tree` → `#walk_shown_tree`, `EventQueue#on_loop_thread?`
→ `#in_loop_thread?`. This was separable from everything else in this file: under
every candidate spelling below, a tree walk and a thread predicate do not belong
in the event namespace, so it did not have to wait on `Q_bare_hook_names`.
`walk_` over `each_` because "walk" is already the house word in prose and
`each_*` implies an Enumerator these do not return.

## Two candidate rules, scored against the tree

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

### Proposed synthesis

The prefix answers **"is there a route the answer steers?"**; the `=` answers
**"who writes it?"**. Two orthogonal questions, one per syntactic feature.

A corollary worth stating because it is the actionable half: **a `handle_` with
no route is a mis-name.** If exactly one component ever sees the event, the
router has already decided, and there is nothing to claim.

### This closes `Q_handler_naming`

`mouse-event-model.md` proposes the vocabulary and calls Up/Drag ambiguous
"since nothing else can claim them". Under Rule B that sentence *is* the answer —
no competitor means no route means `on_`:

```
handle_mouse_down    tunnels; someone claims it        → handle_
handle_mouse_scroll  bubbles until consumed            → handle_
on_mouse_up          goes to the grabbed component     → on_
on_mouse_drag        same                              → on_
on_mouse_move        fan-out, unrefusable              → on_
on_mouse_enter/exit  same                              → on_
```

If this note lands, `mouse-event-model.md`'s `Q_handler_naming` should be struck
and replaced with a pointer here.

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

### `Q_accessor_discipline` — is "remember `attr_writer`" acceptable?

Raised because a rule you must *remember*, whose violation is silent (Ruby warns
on method redefinition only under `-W`), is a bad rule. Two escapes were
considered and one works.

**Escape 1, rejected: make `on_` slot-only and rename the hooks to `handle_`.**
This does not remove the two-meanings problem, it relocates it somewhere with no
syntactic marker. Today `on_foo` and `on_foo=` are distinguished by the `=`;
after the rename `handle_key` (a router reads the verdict) and
`handle_theme_changed` (returns nothing, unrefusable) are distinguished by
nothing at all. It also discards the router axis, makes `handle_attached` read as
refusable, and costs a 13-hook rename across `lib/`, `spec/`, `book/`, rdoc and
`sig/`.

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

**Escape 3, accepted in principle: stop sharing the name.** See
*What other toolkits do* below — no surveyed toolkit lets the override point and
the listener slot share a name, and `R_hook_vs_listener` has the survey.

A tripwire is still worth having as a backstop for whatever spelling wins, since
the collision is derivable from the tree with no allowlist — the house pattern,
cf. "`nomenclature_spec.rb` is the guard and holds no allowlist":

```sh
hooks=$(grep -rhoE "def on_[a-z_]+\??=?" lib/ --include=*.rb | sed 's/def //' | grep -v '=$' | sort -u)
readers=$(grep -rhoE "attr_(accessor|reader) :on_[a-z_]+" lib/ --include=*.rb | sed 's/.*:on_/on_/' | sort -u)
comm -12 <(echo "$hooks") <(echo "$readers")   # must be empty
```

Measured 2026-09-17: 18 hook names, 16 reader names, **zero overlap** — it passes
today and needs no list to maintain. Dropped into
`design/verify_design_tripwires.sh` it fails `rake check` loudly. But it guards
only the `attr_accessor` half; the `on_foo&.call` half above is not greppable
against a hook list without also listing every firing site, which is why the
spelling has to change rather than be policed.

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

### The two spellings on the table

Both separate the names, so both satisfy the finding. They are not equal.

**(a) `fire_theme_changed` + `on_theme_changed=`.** Renames the smaller side
(2 names). But no surveyed toolkit decorates the override with the *raiser's*
verb — .NET uses `On`, Qt a noun suffix, Swing `process` — and `fire_` names an
app's reaction after what the framework is doing to it. Worse, it **breaks the
additive upgrade**: if only dual names take `fire_`, then adding a slot to an
existing `on_attached` renames the hook, so the cheap upgrade becomes a breaking
one; and if *all* hooks take it, `fire_attached` reads wrong.

**(b) `locale_changed()` + `on_locale_changed=`.** The mirror of .NET — bare name
for the override, `on_` for the slot — which is the JS/DOM/Android reading of
`on_`, and is the Cursive direction (decorate the slot). It is the stronger
option:

- **All 18 slot names survive**, including the published
  `label.on_theme_changed = …` in `book/06-theming.md`, `book/10-locale.md`, two
  examples and the rdoc.
- **Additivity is preserved** — a bare hook that later gains a slot adds
  `attr_accessor :on_foo` with no rename on either side. This is exactly what
  (a) loses.
- **`on_foo&.call` becomes correct rather than a trap**: `on_foo` really is the
  reader, and the quiet failure above cannot be written.

`Q_bare_hook_names` — (b)'s cost is that bare hook names are fine for the
`*_changed` / `*_mutated` / `*_removed` family (11 of 15) and poor for the other
four. `attached` sits next to the existing `attached?` predicate; `focus` and
`blur` read as imperatives (`component.focus` = "focus it", which is what
`screen.focused=` does), and `focused` would collide with `Screen#focused`.
Options: exempt those four and keep `on_`, accepting one documented exception;
or find participle forms that do not collide (`gained_focus` / `lost_focus` read
well, `attached` / `detached` do not improve). Note the four are also the least
likely to ever want a slot, which is what makes an exemption cheap — but an
exemption is also exactly the conditional this whole section is trying to kill.

**Direction of upgrade.** Hook → hook+slot is *additive*: add the writer, add
`@on_foo&.call` to the base body, done. Slot → hook+slot is *breaking*:
`attr_accessor` already published a reader that has to be deleted. So **a name
that might ever be both should ship the hook first.**

The additive direction holds only if every override calls `super`, and the gem
already violates that on hooks whose base body is currently empty:

- `ProgressBar#on_attached = sync_ticker` — no `super`
- `Box#on_child_visibility_changed(_child) = relayout` — no `super`

Harmless today. The day `on_attached` grows a slot, a `ProgressBar` silently
never fires the app's listener — no raise, no warning. Only `on_theme_changed`
and `on_locale_changed` document `super` as mandatory, and those are precisely
the two that already have slots; the discipline was written reactively, after the
need appeared.

The cheap fix is to make it proactive: **an `on_` hook's rdoc demands `super`
from day one, empty base body or not.** That is what buys the additive upgrade,
and it costs a sentence.

## Visibility — the open half

The proposal on the table is **handlers and hooks protected, slots public.** It
is not what the tree does.

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

`Q_paste_verdict` — is `handle_paste` an `on_paste` (nothing consults its
answer), or does the Boolean become real? Note the rdoc-published example returns
`true`, so dropping the verdict is a documented-behaviour change, cheap but not
invisible.

## What graduation looks like

- The prefix rule and the `=` rule → lines under a new *Handler naming* heading
  in `AGENTS.md` *Invariants* (~1 KB; headroom at time of writing is 4.6 KB).
- The roads not taken — Rule A, why the 13 hooks are not `handle_`, the
  `attr_accessor` collision, the upgrade direction → `D_handler_naming` in
  `decisions.md`.
- `mouse-event-model.md`'s `Q_handler_naming` struck, its vocabulary fixed to the
  table above.
- Whatever `Q_handler_visibility` settles to → one more `AGENTS.md` line, or a
  note in `D_handler_naming` if the answer is "convention, not enforcement".
- The two `super`-less overrides fixed, if the proactive-`super` rule lands.
- `Q_accessor_discipline`'s check → `design/verify_design_tripwires.sh`, and the
  two rejected escapes → the roads-not-taken half of `D_handler_naming`.
