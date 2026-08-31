# Confirm dialog (and the info dialog) — the API is the whole problem

**Status:** IMPLEMENTED, 2026-08-31 — `Component::ConfirmWindow` shipped with
spec, rdoc, `D_confirm_window`, CHANGELOG and README row. The decision half of
this file has graduated to `DECISIONS.md`; what keeps the file alive is the
**book half** (a batteries-included-windows section covering the confirm
dialog) — once written, retire this note and drop the "Confirm Dialog" Tier 1
row (with its fold-`PickerWindow`-in suggestion) from `ideas/new-components.md`.
Two tangents were spun off rather than resolved here: `ideas/modal-backdrop.md`
(dim/shadow under modals) and `ideas/infowindow-message.md` (migrating
`InfoWindow` to `message=`).

**Unblocked, 2026-08-30:** the `HasContent` question this file flagged for a
separate session was settled and shipped — `Component::Slot`, a re-scoped
`HasContent`, and final tree methods (`D_slots`, `D_final_tree`). The seal this
design needed no longer exists; see "Resolved: nothing to seal" below.

Roadmap entry this comes from: `ideas/new-components.md`, Tier 1, "Confirm
Dialog | `Popup`+`Window`+`Button` | fold `PickerWindow` in". **The
fold-in is rejected** — see the last section.

## What is being proposed

A batteries-included "ask the user a yes/no question" window, in the
`InfoWindow` / `PickerWindow` / `LogWindow` family: a caption, a body of
prose, and a row of buttons. Plus the one-button degenerate case (the info /
alert dialog).

## Constraints the codebase already imposes

Researched before designing; each of these prunes the space, and three of them
kill an option outright.

1. **Callback-only. A blocking `confirm?` returning a bool is impossible.**
   Tuile is single-threaded: `Screen#run_event_loop` is
   `$stdin.raw { event_loop }` with a key thread already running, so a
   value-returning modal would need a nested loop re-entering raw mode. This
   kills the shape everyone reaches for first (JOptionPane, tkinter
   `askyesno`, `tty-prompt`'s `yes?`, GTK3 `dialog.run()`) and is why the
   candidates below are all callback-based. Worth stating in the eventual
   `D_` entry, because it is the first thing a contributor will try to "fix".

2. **Dismissal is an outcome, and this decides the API more than button
   counts do.** ESC, `q` (`Popup#handle_key`) and an outside click
   (`D_outside_click`) all detach the popup. `Overlay#on_close` fires on
   *every* departure — `close`, a direct `Screen#remove_popup`, an outside
   click, teardown via `Screen#close` — which is the exactly-once hook.
   **Any candidate API must answer "what fires on ESC".**

3. **`D_popup_open` bans *inherited* class factories, not class factories.**
   `InfoWindow.open`, `PickerWindow.open` and `Notification.show` all stand,
   explicitly ("Not extended to the batteries-included windows"), because each
   names its own class and takes that class's own arguments. So a class-level
   entry point is available to us.

4. **Top-down layout: the dialog may measure content it *owns*, never content
   injected into it.** `Notification#reposition` is the standing precedent —
   it derives width and height from its own messages. The v0.9.0 re-grow rule
   permits exactly this ("an optional, read-only, caller-side query — measure
   this so *I* can compute a rect and set it top-down"). Inheriting `Popup`'s
   `Fraction::HALF` for a "Delete?" box would look absurd.

5. **Naming: the family is `*Window`, and "dialog" is already taken.**
   `InfoWindow` / `PickerWindow` / `LogWindow` are `Window` subclasses, usable
   tiled *or* popped via a class-level `open`, and book ch7 groups them as
   "batteries-included windows". Meanwhile `Popup`'s own rdoc and the README
   table both call `Popup` "the modal dialog".

6. **Not a `HasValue`.** A dialog outcome is not a field value — same
   reasoning that keeps `ProgressBar` out of the mixin (`D_progress_bar`).

7. **`Button.new("Save") { save! }` is already caption-plus-action.** Any
   `[[label, symbol], …]` list is a worse restatement of a type that exists.

## Prior art, by the axis each lands on

| API | Shape | What it teaches |
|---|---|---|
| Swing `JOptionPane.showConfirmDialog` | ~20 static overloads → `int` | The explosion. Only survivable because it *blocks* |
| Vaadin `ConfirmDialog` | setters + `setCancelable`/`setRejectable` + 3 fixed slots | Three named slots is enough for real apps; the booleans are a Java artifact |
| Android `AlertDialog.Builder` | fluent builder; positive / negative / neutral | Same three slots, reached by builder instead of ctor |
| Qt `QMessageBox` | `StandardButtons` flags **+** `addButton(text, role)` | Escape hatch *beside* the preset — flags for the 90 %, `addButton` for the rest |
| Electron `showMessageBox` | `buttons: [labels]`, result = index | N buttons, zero API growth; caller writes a `switch` |
| prompt_toolkit `button_dialog` | `buttons: [(label, value)]` → value | Same, typed |
| Turbo Vision `messageBox(text, flags)` | bitflags → `cmYes`/`cmNo` | The TUI ancestor; flags again |
| Textual | user subclasses `ModalScreen[bool]` | No dialog component at all — modern TUIs punt entirely |

**The finding:** Java/C++ APIs pay for a builder or a flags enum because they
cannot say *"absent argument = absent button"*. Ruby can. That single fact
deletes Vaadin's `cancelable` / `rejectable` booleans outright and halves the
kwargs surface — the explosion is much less threatening here than the Java
precedent suggests. What kwargs still cannot say: a fourth button, button
order, per-button styling.

## Settled — the body is `text=`, and there is no content slot

The body is a `StyledString` rendered by a `TextView` the dialog owns. No
caller-supplied body component, in either the confirm or the info form.
Owner's call, and I agree; the reasoning is worth keeping because two of the
three payoffs are non-obvious.

**Buy 1 — owning the body is what makes the scrolling *reachable*.**
`TextView#handle_key` acts on the key alone; its rdoc says so explicitly
("hand-feeding a key to an unfocused view scrolls it — dispatch gates on
focus, this doesn't"). And `Button#handle_key` claims only Enter and Space,
returning `false` for everything else. So arrows bubble from the focused
button up to the dialog, which hand-feeds them to the body:

| Key | Goes to |
|---|---|
| Up/Down, PgUp/PgDn, Ctrl+U/D, Home/End, `g`/`G` | hand-fed to the body — scrolling needs no focus change |
| Left/Right, Tab | the button row |
| Enter/Space | the focused button |
| other printables | the mnemonic map (see Mnemonics below) |
| ESC/`q`, outside click | dismiss |

The hand-feed set is everything `TextView#handle_key` claims, `g`/`G`
included — TextView's aliases for Home/End and the less/vi pager idiom, kept
for the fingers that expect them. The three printables the dialog thereby
claims for itself — `q` for dismissal, `g`/`G` for scrolling — are **reserved
against mnemonics at registration** (see Mnemonics), so at keypress time the
two sets are still disjoint and no shadowing rule exists.

With an arbitrary content component none of that routing is sayable, and
"scrolling for free" degrades to "scrolling you can only reach by tabbing into
inert prose".

**Buy 2 — the sizing rule stops having two modes.** The alternative was
"measure own text, *unless* the caller assigned content, in which case they
own the size". That conditional dies: the dialog always owns its content, so
`reposition` measures unconditionally, `Notification`-style. No mode flag, and
no half-configured state where the auto-size measures text no longer on screen.

**Buy 3 — one seam.** `text=` takes a `StyledString`, which on a TTY already
covers icons, color, emphasis, and box-drawing "tables". The things it doesn't
cover aren't confirm dialogs.

**The casualty, priced.** Exactly one real use case is lost, and it is the one
Vaadin's own docs carve out: *"isn't meant for collecting user input, except
for a Checkbox used for remembering the user's choice"* — the don't-ask-again
box. Everything else people reach for (a form, a file picker, a diff view)
isn't a confirm dialog at all, and the escape hatch already exists and is
better than a content slot would be: `Popup.new(content: my_layout)`. The
batteries-included window is sugar over the general mechanism; the general
mechanism stays available. Same shape as `D_box_layouts` declining `Min`/`Max`
and pointing at a rect-callback `Absolute`.

**Re-grow rule for the `D_` entry:** if don't-ask-again ever lands, it comes
back as a *named seam* — a `remember:` label whose state reaches the callback
— never as a reopened general content slot.

### Resolved: nothing to seal — the dialog is not a `HasContent`

*(Was: "the inherited `content=` has to be sealed", with a flag saying the
mixin needed arguing on its own. It was argued, and the seal is gone.)*

The `HasContent` rework shipped in 0.14.0 (`D_slots`, `D_final_tree`). Three
things changed that this design depended on:

1. **`HasContent` no longer means "a component with one child."** It means *I
   own exactly one child directly*, and it is for content that is permanent and
   integral. A dialog has a body, a button row and (maybe) more — it simply does
   not include the mixin, so there is no inherited public `content=` to seal and
   no `raise` to write. The trap is gone rather than signposted.
2. **`Component::Slot` is how a region is held.** The body is a `Slot`; the
   button row is a `Slot` or a plain `Horizontal` child. A slot is wired once at
   construction and its occupant swapped through `slot.content =`, so the
   dialog never computes an insert index and never has to care which regions
   happen to be occupied.
3. **`children` and `parent` are final.** The shape this file originally
   assumed — include `HasContent`, then also `add_child` the buttons — would
   have left `HasContent#handle_mouse` forwarding to the body only, and every
   button unclickable. That failure mode is what forced the rework.

So the structure is a `Popup` (or `Window`) over a `Vertical` of slots, and the
dialog's own accessors name its regions.

### The body accessor: `message=`, stored as given

`message=` accepts `String | StyledString | Component | nil` and populates the
body slot, coercing text to the component that renders it. **The reader returns
what was assigned** — set a `String`, read a `String` back — with the rendering
derived, not substituted.

That deliberately breaks the pattern `Label#text` and `TextView#text` follow
(assign a `String`, read a `StyledString`), and the distinction is the rule to
write into the `D_` entry:

> A setter that **normalizes within a kind** stores the normalized form
> (`String` → `StyledString`: text stays text, and the round-trip is pinned).
> A setter that **changes the kind** stores the input and derives the rendering
> (`String` → a component: handing back the `Label` would be handing back the
> machinery).

Cost, accepted: the reader's type is a four-way union, and there are two stored
values. The second is fine and worth one sentence in the entry so a reader who
knows `D_tree_api`'s desync rule doesn't flag it — that rule is about a second
copy of *tree structure*; here the slot's occupant is *derived* from the raw
value through a single write path, so the two cannot disagree.

**Coercion lives on the dialog, not on `Slot`.** Putting it in `Slot#content=`
so every slot accepted text was tempting and is wrong: the right wrapper differs
per region. A caption-ish line wants a `Label` (ellipsizes); a message wants a
`TextView` (wraps). One `Slot`-level answer would be wrong half the time in this
very component.

**No `header=`.** It would be the title, and `HasCaption#caption` already is —
two accessors for one thing, one of them with an as-is reader and one coercing,
is exactly the wart the rule above exists to prevent. If a *rich* header ever
appears (an icon beside the text), it comes back as a region distinct from the
title, not as a second name for it.

## Settled — one dismissal channel, N action channels

Every button closes the dialog. A button *with* a block fires it; a button
*without* one is Cancel. ESC, `q`, an outside click and the Cancel button are
all the same event, and `on_dismiss` fires **exactly once, only when no action
button was chosen**.

This is Vaadin's "ESC triggers the action associated with the Cancel button"
rule minus the `cancelable` boolean, and it means the caller never writes a
`case` and never has to reason about which paths exist. `Overlay#on_close`
gives it to us: fire `on_dismiss` from there unless a button already fired
(one bool).

**Every button dismisses, unconditionally — there is no keep-open knob.** The
counter-case was hunted and doesn't exist: a dialog that stays open after a
press is either collecting input (excluded by the no-content-slot decision) or
chaining — "Copy files" → a copy-progress window — and chaining is the
callback's job: it opens the *next* window. Even Vaadin's ConfirmDialog closes
on every button.

**Activation order: mark chosen → close → fire the block.** The bool is set
before `close`, which is what lets `on_close` skip `on_dismiss`; the block
fires *after* close, so a callback that opens a follow-up popup sees clean
focus-repair state (the confirm is already out of `@popups`, so
`@popup_prior_focus` snapshots the right thing), and a raising callback can't
strand a half-open dialog — consistent with "a raising hook propagates".

## Settled — the name is `ConfirmWindow`

It sits in the `*Window` family, obeys the widget-suffix rule and gets
tiled-or-popup for free. `ConfirmDialog` is what everyone searching for it
will type, but Tuile already calls `Popup` "the modal dialog", so that name
implies `< Popup`. The rdoc and README say "the confirm dialog" in prose, so
the search still lands.

## Settled — the component is the builder (D); kwargs factories (A) are the sugar

Four candidates were weighed. **D is the mechanism; A survives as the shape of
the sugar layer; B and C are rejected.** Kept for the `D_` entry:

**A — kwargs only.**

```ruby
Component::ConfirmWindow.open(caption: "Delete Report Q4?",
                              text: "This cannot be undone.",
                              confirm: "Delete", cancel: "Cancel") { delete! }
```

Lovely for the 90 %; dies at button 4, and each new knob (`reject:`,
`on_reject:`, a danger tint) is a constructor parameter forever. As the
*factory* shape those costs never fire — the factories are pinned at one or
two buttons, and new capability lands on the mechanism instead.

**B — buttons as data + one callback** (Electron / Turbo Vision). Rejected —
it **dissolves once D is the mechanism**. Its one advantage over A (N buttons
with zero API growth) is layer 1's job now, with no `case`, no
`[symbol, label]` vocabulary next to `Button` (constraint 7), and no extra
kwargs marking the default and the dismissal. The sugar layer then only covers
the one-and-two-button 90 %, which is exactly where A is lovely and its
weakness never fires.

**C — a separate builder object** (Android-shaped). Rejected outright: a
second class whose only job is to be a half-built dialog, while Tuile
components are already mutable — the builder duplicates the component.

**D — the component *is* the builder. ← chosen.** `X.new.tap { … }` is
already the house idiom (it is in `Popup`'s own rdoc), and `Window` already
works this way (`content=`, `footer=`, `footer_text=`).

```ruby
# Layer 1 — the mechanism. No new vocabulary; buttons are Buttons.
dialog = Component::ConfirmWindow.new("Unsaved changes")
dialog.message = "Save your changes before leaving?"
dialog.button("Save")    { save! }
dialog.button("Discard") { discard! }
dialog.button("Cancel")            # no action == dismissal
dialog.on_dismiss = -> { stay_put }
dialog.open
```

New capability lands as a method or a `button` kwarg, never as a constructor
parameter — the exponential growth never starts.

The sub-question is resolved: **`#button` takes a caption, kwargs and a block,
never a prebuilt `Button`.** The mnemonic decides it — the dialog must both
restyle the caption (the underline cue, below) and wrap the action (mark →
close → fire), and doing either to a caller's `Button` is exactly the spooky
mutation the prebuilt option worried about.

**Initial focus: the first-declared button.** Enter fires the *focused*
button, so first-declared is the default button. A safe-default knob for
destructive confirms (focus Cancel so a reflexive Enter is harmless) can land
later as a `button` kwarg — the growth path D was chosen for.

### The factories — three, and no more

Surveying what toolkits ship (Windows `MessageBoxButtons`, Vaadin, Android,
Qt `StandardButtons`), the recurring sets are OK · OK/Cancel · Yes/No ·
Yes/No/Cancel · Retry/Cancel · Abort/Retry/Ignore. Tuile ships three
class-level factories (each naming its own class — `D_popup_open`-clean):

```ruby
# The acknowledgement — one button, which IS the dismissal.
ConfirmWindow.alert("Export failed", "Contact support@example.com.", button: "OK")

# The question — the block is the action; cancel is the dismissal.
ConfirmWindow.confirm("Delete Report Q4?", "This cannot be undone.",
                      confirm: "Delete", cancel: "Cancel",
                      on_dismiss: nil) { delete! }

# Label sugar over confirm — the other canonical phrasing.
ConfirmWindow.yes_no("Overwrite existing file?", path.to_s) { overwrite! }
```

`yes_no` earns its line because it delegates to `confirm` in one line and is
what half of all callers want. Everything further — `ok_cancel`,
`retry_cancel`, `save_discard_cancel` — is the explosion returning as method
names: each is either a label respelling of `confirm` or (the three-way
unsaved-changes case) five lines of layer 1, too short to deserve a named
wrapper. Windows' six-value `MessageBoxButtons` enum is the tripwire to cite
in the `D_` entry. `confirm` carries `on_dismiss:` because a two-outcome
dialog whose No-path acts ("stay on page") is common enough that dropping to
layer 1 for it would sting.

## Settled — mnemonics: MenuBar's shape, derived from the label, `q` reserved

`MenuBar::Item` already solved this, and it is the sanctioned precedent
(`D_key_dispatch`'s re-grow rule: local sugar over an ancestor's `handle_key`,
never a dispatch phase). Steal it wholesale:

- **A `mnemonic:` kwarg on `#button`**, validated at registration exactly as
  `MenuBar#add_item` validates (single one-column printable, not Space, no
  duplicates — none of those has a sane answer at keypress time), downcased so
  matching is case-insensitive, and **advertised by underlining** the letter
  in the caption (the `cued_caption` treatment). The underline matters doubly
  here: Tuile has no status bar to advertise keys in (`D_status_bar`), so an
  unadvertised mnemonic is a hidden feature.
- **Dialog-level, not `Button`-level.** The window keeps a letter → button map,
  and its own `handle_key` (reached by bubbling from the focused button)
  activates the match through the same mark → close → fire path. `Button`
  stays untouched, the same way mnemonics are a `MenuBar` feature and not an
  `Item` dispatch phase.
- **The default is `mnemonic: :auto`** — derive the first grapheme cluster of
  the caption, **silently skipped** when it is reserved or already taken. An
  explicit letter keeps the raise-at-registration contract; `mnemonic: nil`
  opts out. Two-tier on purpose: best-effort for a derivation the caller never
  chose, strict for one they spelled out. The factories get Yes→`y`, No→`n`,
  Delete→`d` for free — the mnemonic follows whatever the button displays.
- **`q`, `g` and `G` are reserved: an explicit `mnemonic:` naming any of them
  raises at registration, and `:auto` skips them.** `q` is unconditionally the
  do-nothing route out of any confirm dialog, including one that thinks it
  forces a choice — this *inverts* the earlier draft's trap-note (a **Q**uit
  button consuming `q` below the popup via bubbling). Worth a sentence in the
  `D_` entry: the user can always Ctrl+C, so pretending there is no escape
  route just trains people to reach for it. `g`/`G` belong to body scrolling
  (the routing table above). A "Quit" or "Go" button is reachable by
  Tab+Enter, or picks another letter.
- **Space is reserved too** (it activates the focused button — the same reason
  MenuBar rejects it).
- **No shadowing rule exists at keypress time.** The printables the dialog
  hand-feeds or claims (`g`, `G`, `q`) can never be mnemonics — the
  reservation is enforced at registration, where MenuBar already puts every
  rule that has no sane answer at keypress time.

## Settled — the last five

1. **Sizing: measure the content, cap at half the screen.** `reposition`
   measures text + button row (`Notification`-style) and caps at
   `Fraction::HALF` — which is `Popup#declared_size`'s default, so the
   confirm's whole job is to *shrink below* it when the message is short. It
   re-measures freely, not grow-only — a dialog's text changes far less often
   than a toast's. No floor for now; the risk a floor would hedge — a tiny
   yes/no box the user doesn't notice, because modals today neither dim the
   content nor cast a shadow — is really a backdrop problem, spun off to
   `ideas/modal-backdrop.md`.
2. **`InfoWindow` migrates to the same `message=` approach**
   (`Component | String | StyledString | nil`). It is an ancient window, born
   before `TextView` existed — which is why it builds a **`List`** of lines
   that *truncate* where a message should *wrap*, leaving two "here's some
   information" paths behaving differently on a long sentence. Breaking, and a
   separate piece of work: spun off to `ideas/infowindow-message.md`; it does
   not hold this design up.
3. **The body IS a tab stop** — a plain `TextView`, no `ConfirmWindow::Body`
   subclass. Focus opens on the first button; Shift+Tab reaches the body.
   *(Reverses the earlier lean. The arrows reach the prose either way, but the
   stop makes overflowing prose visibly reachable rather than secretly
   scrollable, and it deletes a nested class. It also un-pins the coercion
   target: `message=` wraps text in a bare `TextView`.)*
4. **The button row lives inside the window, not in `Window#footer`.** A
   `Horizontal` of the buttons as the bottom row of the inner `Vertical`
   (body `Expand`, row `Fixed[1]`). The footer paints *over the bottom border
   row*, and `[ Delete ]` glyphs embedded in the border look wrong — the
   border stays clean chrome.
5. **An alert keeps its OK button**, even though ESC/`q`/outside-click already
   close it: Tuile deliberately advertises no quit key (`D_quit_key`,
   `D_status_bar` — there is no status bar to advertise it in), so the button
   *is* the discoverability affordance — and it is clickable, which the keys
   are not.

## Rejected — folding `PickerWindow` in

`ideas/new-components.md` suggests it; the owner resists, and the resistance is
right. `PickerWindow` is a keystroke-addressed, scrollable `List` of up to
`MAX_ITEMS` options with a cursor; a confirm dialog is a short focusable row of
buttons with a default and a dismissal. Folding them yields one widget with two
renderings and a mode flag choosing between them — and the two disagree on
every question that matters (does the cursor roam? is there a default? what
does ESC mean? does a pick close?). What *should* be shared is the API
*shape* — a caption, a set of choices, one callback — not the code.

When this graduates, drop the "fold `PickerWindow` in" note from the roadmap's
Tier 1 row along with the row itself.
