# `handle_key?` — marking the handlers that return a verdict

**Status:** brainstorm, opened 2026-09-17. **The owner is convinced the churn is
worth paying**; what is not settled is the sequencing, the exact member list, and
what `D_key_dispatch` has to say afterwards. Pre-1.0, so backward compatibility
is not a constraint.

Proposal: the four handlers a dispatcher routes take a trailing `?` —
`handle_key?`, `handle_text_input_key?`, `MenuBar#handle_mnemonic?`, and (if it
lands) `handle_mouse_down?` / `handle_mouse_scroll?`. Everything else named
`handle_` keeps its bare name and its `void` return.

## Why this exists

`D_handler_naming` settled that `handle_foo` marks the **override point** and
says nothing about the return: only a routed handler carries a Boolean, the rest
are `void`. That is the right contract, and it leaves one gap — **nothing in the
name says which is which.** `handle_key` and `handle_focus` look identical and
differ in the one thing a caller cares about.

`?` closes it with a marker that is *local*: "does this return a verdict?" is
answerable from the method alone. That is exactly what the router axis
(`D_handler_naming`'s Rule B) could not offer, because "a router consults the
answer" is a fact about a caller in another file.

The same note anticipated this. Scoring the five spellings it wrote that `?`
"is the repair for a design that lost. Had `handle_` kept Rule B's 'a router
reads this' meaning *while* also absorbing the hooks, `?` would have been the
only marker left standing." Narrowing the verdict put us in precisely that
configuration.

## What killed it the first time, and what is left

Three objections were recorded. Two rested on the same premise and do not
survive it.

**`?` does not imply purity in Ruby.** The convention is "returns a boolean-ish
/ answers a question"; `!` means "dangerous variant of a safer sibling", not
"mutates". The stdlib precedent is `Set#add?` and `Set#delete?`: both perform the
mutation and report whether it happened — *do it, tell me if it took*, which is
the shape wanted here.

- ~~"`lib/` has 48 `?` methods and not one names a command, so a mutating
  predicate would be the first."~~ Still true as a count (verified 2026-09-17,
  all 48 are pure queries), but it is a house habit rather than a language rule,
  and a pre-1.0 habit is cheap to revise.
- ~~"The dominant call pattern is wrong for it: of 434 `handle_key` mentions in
  `spec/`, none reads the verdict, and discarding a predicate's answer means you
  called it for the side effect."~~ `set.add?(x)` is routinely called with the
  answer thrown away. Dead.
- **`D_key_dispatch`'s "no gate, predicate or mode flag anywhere in it" — this
  one survives, and it is the real question.** `handle_key?` is ambiguous between
  the past tense ("did you handle it?") and a capability query ("would you handle
  it?"), and the second reading invites a pre-dispatch probe: exactly the capture
  phase deleted in 0.10.0. `Set#add?` escapes this because nobody probes a Set; a
  dispatch ladder is where people reach for `can_handle?`.

`Q_capture_phase_invitation` — is the rdoc enough, given that calling it
*delivers*, so a probe is incoherent and fails loudly the first time anyone
writes one? Or does the invitation itself cost more than the marker is worth?

**Whichever way it goes, `AGENTS.md`'s "no gate, predicate or mode flag anywhere
in it" must be amended to say the prohibition is about dispatch *structure*, not
about a name ending in `?`.** Left as it stands, the invariant reads as
contradicted by the code, which is worse than either answer.

## What it would cost

The largest rename in the plan, and the same bill that sank the `claim_key`
spelling in `D_handler_naming`:

- 434 `handle_key` call sites in `spec/`
- ~27 in `book/` and `examples/`, ~32 rdoc mentions
- the documented `Testing.get(Component::Button, …).handle_key(Keys::ENTER)`
  idiom (`testing.rb:7`), and published rdoc examples
- downstream subclasses — pikuri-tui's `ConfirmerPopup` among them

Mechanical, but it touches every app that ever overrode `handle_key`.

## Open questions

`Q_sequencing` — ride now, or with the mouse model? `mouse-event-model.md`
rewrites dispatch and will churn these call sites anyway, and its new
`handle_mouse_*` names would be *born* with the right spelling instead of renamed
into it. Against: shipping `D_handler_naming` with a split you cannot see from
the name, for however long that gap lasts.

`Q_members` — `handle_key?`, `handle_text_input_key?`, `handle_mnemonic?` is the
list today. `handle_text_input_key?` and `handle_mnemonic?` read clunkier than
`handle_key?`; is that a reason to reconsider, or just how it reads?

`Q_paste_stays_bare` — **settled, and it is the model for the rule.**
`handle_paste` takes no `?` and returns `void`: a paste goes to `Screen#focused`
and stops, never bubbles, and is never replayed as keys, which would fire hotkeys
on the clipboard's contents. A decliner has nowhere to hand it on, so there is no
verdict to report. The test for membership is "is there an alternative delivery
this answer chooses between?", not "could a Boolean be returned?".

`Q_marker_on_the_other_side` — worth checking once: is the marked set the small
one? Four `?` handlers against fifteen bare hooks says yes, and `D_handler_naming`
prefers the marked name on the rare case.

## Related

`D_handler_naming` (which narrowed the verdict and so created this gap; its
`handle_key?` bullet points here),
`D_key_dispatch` (the three-rung ladder with no gates — the one live objection),
`D_bracketed_paste` (why paste has no verdict to carry),
`design/ideas/mouse-event-model.md` (`Q_sequencing` turns on it; its handler
table is where the new names would be born).
