# Confirm dialog (and the info dialog) — the API is the whole problem

**Status:** design, 2026-08-30. Nothing built. The implementation is trivial —
a `Window`, a body, a row of `Button`s. What is hard is the API, because every
framework that has shipped one has shipped a combinatorial explosion with it.
Two things are **settled** below (no custom body; one dismissal channel); the
button-declaration API has a recommendation and the open questions at the
bottom are the point of this file.

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
| Up/Down, PgUp/PgDn, Ctrl+U/D, `g`/`G` | the body — focus never leaves the buttons |
| Left/Right, Tab | the button row |
| Enter/Space | the focused button |
| ESC/`q`, outside click | dismiss |

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

### Consequence: the inherited `content=` has to be sealed

`ConfirmWindow < Window` inherits a public `content=` from `HasContent`.
`InfoWindow` leaves it open and that is harmless there — reassigning just
swaps the list. Here it is not: reassigning destroys the button row *and*
leaves `reposition` measuring text that is no longer displayed. Silent
corruption, not "you get what you deserve". Cheapest honest fix — content is
set once, by the constructor, and a second assignment raises with a message
naming the escape hatch:

```ruby
def content=(new_content)
  raise Tuile::Error, "ConfirmWindow owns its content; set #text= instead, " \
                      "or use Popup.new(content:) for a custom body" unless content.nil?
  super
end
```

One line, and it turns the trap into a signpost at the exact point of
confusion.

> **Flagged, for a separate session:** having to seal an inherited public
> mutator is a symptom, not a fix — `HasContent` hands every includer a public
> `content=` whether or not the includer's invariants survive it. The owner
> calls the mixin an anti-pattern and wants that argued on its own. Do not
> settle it inside this idea; if it *is* reworked, this seal disappears and
> the section above becomes moot.

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

## Open — how buttons are declared

Four candidates, with the recommendation last.

**A — kwargs only.**

```ruby
Component::ConfirmWindow.open(caption: "Delete Report Q4?",
                              text: "This cannot be undone.",
                              confirm: "Delete", cancel: "Cancel") { delete! }
```

Lovely for the 90 %; dies at button 4, and each new knob (`reject:`,
`on_reject:`, a danger tint) is a constructor parameter forever.

**B — buttons as data + one callback** (Electron / Turbo Vision).

```ruby
ConfirmWindow.open("Unsaved changes", choices: { save: "Save", discard: "Discard" }) { |c| … }
```

Scales freely, but the caller writes a `case` for the two-button case, and it
invents a `[symbol, label]` vocabulary next to `Button`, which already is one
(constraint 7). Needs extra kwargs to say which choice is default and which is
the dismissal.

**C — a separate builder object** (the `tap`-DSL sketch, Android-shaped).
Scales, one block per button, no `case`. Cost: a second class whose only job
is to be a half-built dialog — while Tuile components are already mutable, so
the builder duplicates the component.

**D — the component *is* the builder. ← recommended.** `X.new.tap { … }` is
already the house idiom (it is in `Popup`'s own rdoc), and `Window` already
works this way (`content=`, `footer=`, `footer_text=`).

```ruby
# Layer 1 — the mechanism. No new vocabulary; buttons are Buttons.
dialog = Component::ConfirmWindow.new("Unsaved changes")
dialog.text = "Save your changes before leaving?"
dialog.button("Save")    { save! }
dialog.button("Discard") { discard! }
dialog.button("Cancel")            # no action == dismissal
dialog.on_dismiss = -> { stay_put }
dialog.open

# Layer 2 — sugar over it. Class-level, naming its own class (D_popup_open-clean).
ConfirmWindow.confirm("Delete Report Q4?", "This cannot be undone.",
                      confirm: "Delete") { delete! }
ConfirmWindow.alert("Export failed", "Contact support@example.com.")
```

The sugar is three lines calling the mechanism. New capability lands as a
method or a `button` kwarg, never as a constructor parameter — the exponential
growth never starts. Open sub-question: does `#button` take a caption and a
block, or an already-built `Button`? The former hides the closing behavior
(the dialog wraps the action); the latter is more composable but means wrapping
a caller's `on_click`, which is spooky.

## Open questions

1. **Name.** `ConfirmWindow` sits in the `*Window` family, obeys the
   widget-suffix rule and gets tiled-or-popup for free. `ConfirmDialog` is what
   everyone searching for it will type, but Tuile already calls `Popup` "the
   modal dialog", so the name implies `< Popup`. Leaning `ConfirmWindow`, with
   the rdoc and README saying "the confirm dialog" in prose.
2. **Sizing specifics.** Measure text + button row in `reposition`, capped at
   a fraction of the screen — but which fraction, and is there a floor like
   `Notification::MIN_CAP_WIDTH`? Also: does it grow-only, as `Notification`
   does, or re-measure freely (it should re-measure — a dialog's text changes
   far less often than a toast's).
3. **Mnemonics — `y`/`n`?** This is the one place `PickerWindow`'s trick is
   genuinely tempting. `D_key_dispatch` deleted framework mnemonics; `MenuBar`
   re-added them locally as sanctioned sugar over `handle_key`, which is the
   precedent to follow if we do it. **The trap to document:** `Popup` claims
   `q`, so a dialog with a **Q**uit button must consume `q` below it. Bubbling
   makes that work (the window sees the key before the popup), but it wants
   saying out loud.
4. **`InfoWindow` is now inconsistent with the family.** It builds a **`List`**
   of lines, which truncates rather than wraps, while the new alert body would
   be a `TextView`, which wraps — so two "here's some information" paths behave
   differently on a long sentence. Three ways out: (a) leave it, and keep the
   book's framing that `InfoWindow` is a scrollable list of *lines* while
   `alert` is a *message* plus an acknowledgement; (b) move `InfoWindow` to
   `TextView` + `text=`, breaking (`lines` array → `StyledString`) but coherent;
   (c) let `alert` subsume the popup use and leave `InfoWindow` as the tiled
   line-list. Leaning (a) for now, revisit at the CHANGELOG stage — it is a
   separate decision and should not hold this one up.
5. **Is the body a tab stop?** `TextView#tab_stop?` is `true`, so Tab would
   visit inert prose between the caption and the buttons. Since arrows already
   reach it, make it not one — a private nested `ConfirmWindow::Body <
   TextView` overriding `tab_stop?`, same shape as `MenuBar::Cascade` and
   `TextArea::WrappedText`. Minor, but it is the difference between a 2-stop
   and a 3-stop dialog.
6. **Where does the button row live — is it the `Window#footer`?** A button
   row is exactly one row spanning the inner width, which is what `footer=`
   already is. That would make the structure `content = TextView` +
   `footer = Horizontal(buttons)` with no `Vertical` wrapper at all, and would
   change what "sealing `content=`" even means. Against it: the footer paints
   *over the bottom border row*, and `[ Delete ]` glyphs in the border may look
   wrong. Needs a mock-up before deciding.
7. **Does an alert need an OK button at all**, when ESC/`q`/outside-click
   already close it? Yes — and the reason is worth writing down: Tuile
   deliberately advertises no quit key (`D_quit_key`, `D_status_bar` — there is
   no status bar to advertise it in), so the button *is* the discoverability
   affordance.

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
