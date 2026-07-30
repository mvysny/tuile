# Key dispatch: who wins a keystroke?

**Status:** open — deliberately undecided. Raised 2026-07-30 out of
`ideas/checkbox.md`'s "Space vs the global shortcut scan" question, which
turned out to be a symptom of a bigger topic. **The gate is not to be
changed until the framework survey below is done.** `AGENTS.md`'s
"key-dispatch ladder" section documents what Tuile does *today*; this note
is about whether that's what it should do.

There is one live API defect noted at the bottom which may deserve fixing
ahead of the broader decision.

## What Tuile does today

The ladder, verified in code 2026-07-30 (`AGENTS.md` has the diagram):

1. **TAB / SHIFT_TAB** — `Screen#handle_key`, unconditional. No component
   ever sees Tab.
2. **`@global_shortcuts`** — the app registry. Printable keys *raise* at
   registration (`screen.rb:373`); so do TAB/SHIFT_TAB.
3. **CAPTURE** — `ScreenPane#handle_key` scans `find_shortcut_component`
   across the whole scope, **focuses** the match, consumes the key. Skipped
   while `screen.cursor_position != nil`.
4. **DELIVERY** — `bubble_key`: focused component, then up the ancestor
   chain to the scope root; first `handle_key` returning true wins.

Two details that keep being mis-remembered, so state them plainly:

- `key_shortcut` **focuses; it does not activate** (`component.rb:124`). A
  rogue `key_shortcut = " "` doesn't fire someone else's action instead of
  toggling a focused checkbox — it *moves focus* to that widget.
- `Screen#cursor_position` is `@focused&.cursor_position` (`screen.rb:548`),
  so the capture suppression is **already** scoped to the focused component
  alone. It is not "any component with a cursor gets special treatment."

## The question, split in two

The original framing ("ban Space, or let a focused component's consumption
suppress the shortcut?") conflated two independently changeable things.
Keep them apart or the discussion goes in circles:

- **The ladder** — should CAPTURE come before DELIVERY at all? Option B
  below inverts it.
- **The gate** — what suppresses CAPTURE? Today: "the focused component
  owns the hardware cursor." Option C replaces the proxy without touching
  the ladder. **This is where the actual discomfort is** (see the
  objection), so it is the most promising axis.

## Options on the table

### A. Document it, ban printable shortcuts by convention

Cheapest. Consistency, not a new rule: `register_global_shortcut` *already*
raises on printables, and its error message redirects the author to
`key_shortcut`. Extending "don't bind printable keys" to `key_shortcut` by
documentation closes `checkbox`'s question outright — `key_shortcut = " "`
("Space focuses this widget") is close to nonsense anyway.

Open sub-choice if this wins: leave `key_shortcut=` unvalidated (chosen for
now), `Tuile.logger.warn`, or raise. A raise is a behavior change to a
shipped API guarding a hazard nobody has hit.

### B. Invert: a focused component that consumes the key suppresses capture

Appealing because it deletes a special case — "you're either focused or you
aren't." Arguments *against*, gathered 2026-07-30:

- **Tab points the other way.** Tab is claimed unconditionally at the top,
  even over a `TextArea` where inserting a literal tab would be sensible.
  So Tuile's existing answer to "who wins" is a *fixed ladder*, not
  "whoever is focused". Under a focus-wins rule, a component that swallows
  Tab **traps focus with no keyboard way out** — the unconditional claim is
  a safety property, not a convention. (The `CheckboxGroup`-eats-Tab
  thought experiment is what surfaced this.)
- **Mnemonics become unreliable, invisibly.** `key_shortcut` exists to
  capture from anywhere. Under B it works or not depending on where focus
  happens to be — a failure the author cannot see, growing with the tree.
  Today's failure mode is *static*: a property of the app's own two
  bindings, discoverable at design time by whoever wrote both.
- **For a `TextField` it changes nothing** (a focused text field consumes
  printables either way). B only differs for *non-cursor* focused
  components — the narrow band where capture is most defensible.
- **Cost/benefit:** deletes one conditional; hands the app author an
  unbounded "does this key still work when focus is there?" question.

### C. Keep the ladder, replace the gate with an explicit declaration

The objection that motivates this (2026-07-30, and the reason the decision
is parked): *a component gets different treatment because it happens to own
a hardware cursor.* That's an implementation detail standing in for the
thing we actually mean — "I am in text-entry mode, printable keys are
mine." A checkbox could grow a cursor in theory and would silently change
key routing; conversely a component could swallow typing without owning a
cursor and gets no protection.

So: keep capture-before-delivery, but gate it on a **declared predicate**
rather than the cursor. Sketch, name TBD — `text_entry?` /
`consumes_printable_keys?` / `swallows_typing?`; default `false`,
`true` on `AbstractStringField`. Notes:

- It probably wants to be *per-key*, not a blanket flag: "printables are
  mine" is the honest claim, and it's what the suppression is actually for.
  A blanket flag would also suppress unprintable shortcuts, which today's
  gate does too — is *that* right? (Currently `^L` is swallowed while a
  text field is focused only if bound via `key_shortcut`; via the registry
  it fires, because the registry sits above the pane.)
- It keeps `cursor_position` for what it's actually about — where to park
  the hardware cursor — instead of overloading it as a routing signal.
- Migration is mechanical and the behavior is identical on today's
  component set, so it's a refactor with an open naming question, not a
  redesign.

### D. Do nothing at all

The status quo has shipped and nobody has hit it. Listed for completeness;
A is strictly better since it costs only prose.

## Before deciding: survey what other frameworks do

The reason this note exists rather than a decision. Worth an afternoon,
because the vocabulary is well-trodden and Tuile shouldn't invent a fourth
model. Questions to answer for each: what are the dispatch phases, does
capture precede delivery, what suppresses an accelerator, and is a
"default button" a global binding or a scoped fallback?

- **Swing** — `InputMap`/`ActionMap` with `WHEN_FOCUSED`,
  `WHEN_ANCESTOR_OF_FOCUSED_COMPONENT`, `WHEN_IN_FOCUSED_WINDOW`. The three
  scopes are exactly this problem, named. `JRootPane#setDefaultButton` is
  the default-button precedent and is *window*-scoped, not global.
- **Win32 dialogs** — `IsDialogMessage`, `WM_GETDLGCODE`
  (`DLGC_WANTALLKEYS` / `DLGC_WANTCHARS`) — a control *declares* what it
  wants to swallow. That is option C, thirty years earlier, and worth
  reading before naming the predicate.
- **The web / DOM** — capture vs bubble phases, `preventDefault`, and
  `beforeinput`; plus the accessibility conventions for what a focused
  widget owns.
- **Vaadin** — `Shortcuts`/`ShortcutRegistration` (`listenOn` scoping,
  `allowBrowserDefault`, `bindLifecycleTo`). Closest to Tuile's own
  component model, so its scoping vocabulary is the most transferable.
- **Other TUIs** — Textual (`BINDINGS`, `key_*` handlers, and its
  bubbling `on_key`), Ratatui/Bubbletea (explicit, no dispatch at all —
  useful as the "what if we had no ladder" baseline), ncurses apps.
- **GTK** — `gtk_widget_add_controller` / `GtkShortcutController` phases
  (`CAPTURE`/`BUBBLE`/`TARGET`), mnemonics.

## Enter, and the default-button pattern

Settled enough to record as a *finding* rather than a decision, since it
needs no new machinery:

**A default button is not a global listener; it is an ancestor-level
fallback, and `bubble_key` already gives it correct semantics.** Put the
Enter handling on the form/window ancestor:

| focused widget | Enter | outcome |
|---|---|---|
| `TextArea` | consumes (newline) | form never sees it ✓ |
| `TextField` with `on_enter` | consumes | no double-submit ✓ |
| `TextField` without | declines | bubbles → submit ✓ |
| `Button` | consumes | activates *itself*, not the default ✓ |
| `Checkbox` | declines | bubbles → submit ✓ |

Consequences:

- This is *why* `checkbox`'s "Enter deliberately does nothing" is right —
  its note said "Enter should stay free for a form's submit", and this is
  the mechanism that makes the sentence real.
- Because `bubble_key` stops at the scope root, two forms in two popups
  each get their own default — which a global registry structurally cannot
  do. Ancestor scope is what makes it composable.
- A future `Window#default_button=` is a five-line ancestor `handle_key`,
  not new dispatch machinery. (Swing agrees: `JRootPane`, window-scoped.)

## Live defect: the registry accepts editing-relevant unprintables

Independent of everything above, and arguably fixable now:

`ENTER == "\r"`, so `Keys.printable?` is false, so
`register_global_shortcut(Keys::ENTER) { submit }` is **legal today** — and
rung 2 sits *above* the pane with no cursor-owner suppression whatsoever.
So the obvious way to build a default button silently breaks `TextArea`'s
newline and `TextField#on_enter` app-wide. Same exposure for `BACKSPACE`
and the arrow keys. The registry's own error message advertises the
cursor-owner suppression as though it applied to itself; it doesn't — that
suppression is rung 3's.

Options: give the registry the same cursor-owner gate the pane has; reject
a small reserved set (`ENTER`, `BACKSPACE`, arrows) exactly as it already
rejects TAB; or document that unprintable-but-editing-relevant keys are the
caller's problem. **Leaning: reject the reserved set** — it matches the
existing TAB precedent, fails loudly at registration rather than mysteriously
at runtime, and the error message can point at the ancestor-`handle_key`
pattern above.

## Graduation

- Whichever of A/B/C wins → `DECISIONS.md` as `D-key-dispatch`, carrying
  the rejected options *and* the framework survey (that's the part nobody
  will redo).
- The ladder itself is already in `AGENTS.md`; only amend it if the
  decision changes behavior.
- The Enter/default-button finding graduates to the book's components or
  events chapter as the documented way to build a form.
- Retire `checkbox`'s "Space vs the global shortcut scan" question — it
  points here now.
