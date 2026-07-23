# IntegerField — the second typed input, and a HasValue stress-test

**Status:** DESIGN SETTLED, not yet implemented — this note is the
complete spec to build from a fresh context. Its real job is to *validate
the `HasValue` seam* ([`has-value.md`](has-value.md), `DECISIONS.md`
`D-has-value`): that note explicitly parked IntegerField as "the second
typed component" whose landing would tell us whether the seam holds up
when `value`'s type genuinely diverges from the editing buffer.
`ComboBox` proved the *fully-detached* case (value ⟂ query); IntegerField
probes the *derived* case (value = a parse of the buffer).

## Decisions locked this session (TL;DR)

1. **`IntegerField < Component`, `include HasValue`** — *composes* a
   `TextField`, never subclasses it (a subclass would leak `TextField`'s
   String-typed `text`/`value` seam onto an Integer field's face).
2. **Value is typed:** `Integer` or `nil`, derived by
   `Integer(text, 10) rescue nil`; `empty_value = nil` (not `""`).
3. **Rename `TextInput → AbstractStringField`** (the one breaking move):
   the abstract base of `TextField`/`TextArea`, documented as
   *String-valued only*.
4. **`HasValue` absorbs `focusable? = true`** (only) and becomes the
   "input-field mixin" — de-duplicating what `AbstractStringField` and
   `ComboBox` both define today. **`tab_stop?` does *not* fold in:** it
   diverges. A leaf editable field (`AbstractStringField`) is a tab stop
   (`true`); a composing wrapper (`ComboBox`, and `IntegerField` below)
   is *not* (`false`, inherited from `Component`) — its inner `@field`
   carries the stop, and a wrapper that were also a tab stop would
   double-stop Tab on the same widget (`cycle_focus` collects stops via
   `on_tree`). ComboBox already relies on this (tested: "focusable
   non-tab-stop container"), so IntegerField's wrapper likewise leaves
   `tab_stop?` at the `Component` default — it must **not** define it.
5. **No `AbstractComposedField`, no universal `AbstractField` class.** The
   ~5-line wrapper shell is duplicated between `IntegerField` and
   `ComboBox` on purpose (shallow commonality → duplicate, per `cop`).
6. **The private converter stays private + hardcoded**; input filtering
   via the child's `on_key`; eager per-keystroke firing.

## The spec (from the ask)

- Value is an `Integer` — no decimal point, ever.
- The user may only type `0`–`9` and a leading `-` (negative sign).
- Empty / un-parseable buffer ⇒ value is `nil` (Vaadin's `IntegerField`
  uses `null`; answers open-question #4 in `has-value.md` — empty *is*
  per component: `nil` here, not `TextInput`'s `""`).

Out of scope on purpose: `min`/`max`/`step`, thousands separators,
locale grouping, `+` sign, a ±1 spinner on Up/Down. Note them as natural
futures; don't build them (same "range/format is a form concern" line the
converter debate draws).

## Decision: compose a `TextField`, do NOT subclass it

```
Component::IntegerField < Component   # include HasValue; wraps a @field TextField
```

An earlier draft leaned `IntegerField < TextField`. Rejected. The
decisive reason is **API vocabulary**, not code reuse: subclassing drags
`TextField`'s widget-level, `String`-typed seam (`text`, `text=`,
`on_change(String)`, the `value`/`value=` String aliases from the base)
onto IntegerField's public face, where they sit *next to* the real
`value`/`value=` (`Integer`) as a conflicting, wrong-typed second seam.
Ruby can't cleanly hide inherited public methods (`undef_method` is a
smell and breaks substitutability), so composition is the honest tool for
presenting only the domain API.

**COP framing (see the `cop` skill).** IntegerField is a *domain*
component — its data API is in domain terms, `value` is an `Integer`,
not `text` is a `String` ("`items=`, not `text=`"). You build a domain
component by *configuring a generic one*; here the generic one is
`TextField` (the domain-agnostic text-editing widget). The `cop` skill
blesses `PersonGrid < Grid<Person>` by *inheritance* — the difference is
that `Grid` has **no competing wrong-typed value seam**, so exposing its
`items=` is already clean; `TextField` *does* (String `text=`/`value=`),
so inheriting it would violate "data API in domain terms." This also
makes IntegerField a **simpler ComboBox** — the identical structure minus
the dropdown — a strong consistency win.

## The class hierarchy (the breaking moves to make now)

IntegerField is the trigger to fix the input taxonomy while pre-1.0. The
key fact: `on_enter`/`on_key_up`/`on_key_down` live **only** in
`TextField`; `TextArea` maps Enter to `insert_char("\n")` — Enter is an
*editing* key there, not a discrete action. So a single universal
`AbstractField` *class* owning `on_enter` is **wrong** (TextArea would
inherit a submit callback contradicting its behavior).

**No class root, and no composed-field base.** `HasValue` is the
Ruby-idiomatic `AbstractField`: a mixin *is* how Ruby shares what Java
needs a class for, and `is_a?(HasValue)` is the Binder's marker. And a
`AbstractComposedField` parent for IntegerField+ComboBox was **rejected** —
the genuine shared code is ~5 lines of trivial delegation, exactly the
shallow-commonality shell the `cop` skill says to *duplicate*, not fold
into a base. A class abstraction for five one-liners is machinery that
doesn't earn its place.

```
Component
│   HasValue (mixin) ─ the "input field" mixin: value seam + focusable? (NOT tab_stop?)
│
├─ AbstractStringField < Component   (rename of TextInput; include HasValue)
│    value IS text (String); owns editing machinery, on_change, on_key, on_escape
│    tab_stop? = true (the leaf field IS the stop)
│    ├─ TextField   (adds on_enter, on_key_up/down — Enter is discrete)
│    └─ TextArea    (Enter = newline; deliberately no on_enter)
│
├─ ComboBox     < Component (include HasValue)   wraps a @field TextField (dropdown)
└─ IntegerField < Component (include HasValue)   wraps a @field TextField (digit filter)
        ↑ the ~5-line wrapper shell is duplicated between these two, on purpose
          both inherit tab_stop? = false (the inner @field carries the stop)
```

**`HasValue` grows *one* universal default — and *sheds* duplication.**
`focusable? = true` moves *into* the mixin. It's already duplicated today
(in `AbstractStringField` **and** `ComboBox`), so folding it in
**removes** existing duplication, not just spares IntegerField. This
reframes `HasValue` from a *pure value seam* to the **input-field mixin**
("I hold a value *and* I'm focusable") — Vaadin's `AbstractField` done as
a mixin.

- **`tab_stop?` stays *out* of the mixin — it diverges.** The leaf
  editable field (`AbstractStringField`) keeps its own `tab_stop? = true`;
  the composing wrappers (`ComboBox`, `IntegerField`) inherit
  `Component`'s `false` and delegate the stop to their inner `@field`. A
  wrapper that *were* also a tab stop would double-stop Tab on the same
  logical widget (`cycle_focus` collects stops via `on_tree`, self +
  descendants). ComboBox already relies on this and tests it ("focusable
  non-tab-stop container") — the original draft wrongly assumed both flags
  were duplicated on ComboBox. So IntegerField's wrapper must **not**
  define `tab_stop?`.
- It does **not** reopen the deferred surface: `read_only`/required/
  converters were deferred as *forms* concerns; `focusable?` is an
  intrinsic interaction default, a different axis. Defaults stay
  overridable (a future read-only display sets `focusable? = false`).
- **`on_enter`/`on_key_up`/`on_key_down` stay on `TextField`**; the
  wrappers expose them by *delegating to their inner `@field`* (they
  already hold one). Never on a base above `TextArea`.
- **`on_escape` stays in `AbstractStringField`** (its ESC-handling lives
  in `handle_text_input_key`); wrappers delegate to `@field` or take its
  default.

**The one genuinely-breaking move: `TextInput → AbstractStringField`**
(confirmed name). A public constant rename touching `text_input.rb`,
`text_field.rb`, `text_area.rb`, `has_value.rb`, a spec, AGENTS,
DECISIONS, `sig`, and `book/07-components.md`. Its doc becomes "abstract
base for **String-valued** text editors; a field whose value isn't a
String composes one of these rather than subclassing it." Everything else
(the `HasValue` additions, IntegerField itself) is additive.

## Structure

`< Component`, `include HasValue`. `focusable?` comes from the mixin;
`tab_stop?` is left at the `Component` default (`false`) — do **not**
define it, the inner `@field` is the tab stop. The ~5-line wrapper shell
(`@field` wiring, `children`,
`cursor_position`, `on_focus`, `rect=`) is duplicated with ComboBox on
purpose. Callback delegators (`on_enter`/`on_key_up`/`on_key_down`) can
use stdlib `Forwardable#def_delegators :@field, …` to stay tidy without a
base class.

```ruby
class IntegerField < Component
  include HasValue                                    # value seam + focusable? (tab_stop? stays Component's false)

  def initialize
    super()
    @last_value = nil
    @field = TextField.new
    @field.parent    = self
    @field.on_change = ->(_text) { fire_if_changed }  # text moved -> re-derive value
    @field.on_key    = method(:field_key)             # reject non-digits BEFORE insert
  end

  # --- typed seam (overrides HasValue's nil default) ---
  def value = (Integer(@field.text, 10) rescue nil)   # ""/"-" -> nil ; "007" -> 7 ; "-0" -> 0
  def value=(int)
    @field.text  = int.nil? ? "" : int.to_s           # fires @field.on_change -> fire_if_changed
    @field.caret = @field.text.length                 # park caret at end
  end
  def empty_value = nil                                # empty? => value.nil?

  # --- wrapper shell (duplicated with ComboBox; ~5 lines) ---
  def children = [@field]
  def cursor_position = @field.cursor_position
  def on_focus; super; screen.focused = @field; end
  def rect=(r); super; @field.rect = r; end
  # + Forwardable: on_enter / on_key_up / on_key_down delegate to @field

  private
  def field_key(key)
    Keys.printable?(key) && !accepts?(key)             # true = swallow (caret never moves)
  end
  def accepts?(char)
    return true if char.match?(/\A[0-9]\z/)
    char == "-" && @field.caret.zero? && !@field.text.start_with?("-")
  end
  def fire_if_changed
    v = value
    return if v == @last_value                         # honor "never fires on a no-op"
    @last_value = v
    on_value_change&.call(v)
  end
end
```

`Integer(str, 10)` is the right parser: strict (rejects `"12abc"`, unlike
`String#to_i`), base-10 (so `"007"` is 7, not an octal error), and raises
on `""`/`"-"` so both fall to `nil`.

## The API walk — every `TextInput`/`TextField` member, kept or hidden

| Member | What it is | IntegerField |
|---|---|---|
| `value` / `value=` | HasValue seam | **Own, typed** (`Integer`/`nil`) |
| `empty_value`/`empty?`/`clear` | HasValue | **Keep**, `empty_value = nil` |
| `text` (reader) | raw String buffer | **Hide** — child-internal |
| `text=` | buffer setter | **Hide** — callers use `value=` |
| `caret` / `caret=` | editing index | **Hide** — child-internal |
| `on_change` (String) | text listener | **Consume internally** → re-emit `on_value_change` |
| `on_value_change` | the seam | **Own** (`Integer`/`nil` payload) |
| `on_key` (interceptor) | key hook | **Consume internally** — the digit filter |
| `on_escape` | ESC callback | **Take child default** (clear focus); don't expose — lean toward less surface, revisit only if a distinct cancel is needed |
| `on_enter` | Enter callback | **Delegate** — "submit" |
| `on_key_up`/`on_key_down` | arrow callbacks | **Delegate** for form nav; captured now, reserve for a future spinner |
| `cursor_position` | hardware caret | **Delegate** → `@field.cursor_position` |
| `handle_mouse` | click-to-focus | child handles via normal dispatch; delegate only if needed |
| `repaint` | paint | structural (`super`, gap-leaver); child paints its well |
| `focusable?` | focus gating | **from `HasValue`** now (`true`); `on_focus → focus the child` |
| `tab_stop?` | Tab traversal | **inherit `Component`'s `false`** — don't define; the inner `@field` is the stop |
| `handle_key` | dispatch | routed to child when it's on the focus chain |

## What composition quietly *fixes* (the seam findings, revised)

The inheritance draft surfaced two `TextInput` defects. Composition
dissolves both — which is itself a datapoint on the seam's shape.

1. **The "wrong payload" firing is an *inheritance* artifact, not a live
   bug.** `TextInput#text=` fires `on_value_change(@text)`. For
   `TextField`/`TextArea`, `value == text`, so that is **correct**. It
   would only misfire for a *subclass* whose value ≠ text — which
   composition never creates. IntegerField listens on the child's
   `on_change` (text-flavored, by design) and re-emits its *own*
   `on_value_change(value)` with the parsed Integer; the child's own
   `on_value_change` simply goes unlistened. **So we do not need to touch
   `TextInput`.** (Routing its fire through `value` instead of `@text`
   remains cheap subclass-safety hygiene, but nothing here depends on it.)

2. **The no-op-leak contract gets a proper home.** `"07" → "007"` is a
   buffer change with `value` still `7`. `fire_if_changed` guards on
   `value != @last_value`, so the seam's "never fires on a no-op" promise
   is honored *inside IntegerField*, not patched into `TextInput`.

3. **Caret-drift is gone.** `@field.on_key` is consulted *before* `insert`
   (TextInput#handle_key, line ~131), so swallowing an invalid printable
   there means `insert` never runs and the caret never moves — no
   `preprocess_text` gymnastics, no early-return-before-clamp hazard.

## Firing model & normalization

- **Eager, per-keystroke** (mirrors `TextField#on_change`; the seam
  mirrors it). `1`→`1`, `12`→`12`, transient `-`→`nil`→`-5`. Vaadin uses
  on-blur for numerics, but a TUI has no cheap blur and TextField is
  already eager. There is deliberately no `on_blur` hook; don't invent one.
- **No normalization** in v1: `"007"` shows as typed though `value == 7`;
  `"-0"` shows though `value == 0`. Re-rendering the canonical form needs
  a blur/commit point and risks yanking the buffer under the caret
  mid-edit. Defer to Forms, where a Converter would own formatting anyway.

## The line NOT to cross: private converter, no generic base

"Wire up a small converter" is right — **kept private and hardcoded**
(`Integer(t,10)` / `&:to_s`), exactly as `TextField` hardcodes
identity-String. Do **not**:

- expose a public `converter=` strategy — that is the Binder's job
  (`D-has-value` keeps converters *above* the field), reached in through
  the back door;
- extract an `AbstractConvertingField` base when `DateField` later lands —
  the `cop` skill says duplicate over a shallow-commonality base, and a
  generic converting-field base *is* the converter machinery in disguise.

## Do NOT deprecate `TextInput#text`

Considered and rejected. `text` is the *correct domain name* for
`TextField`/`TextArea` (a text editor's contents genuinely *are* text;
`has-value.md` open-question #2 already landed on "keep both"). The defect
was `text` *leaking onto IntegerField via inheritance* — which composition
removes at the source. TextField keeps `text`.

## Interaction checklist (spec these)

- Empty field ⇒ `value == nil`, `empty? == true`.
- Type `-` alone ⇒ buffer `"-"`, `value == nil` (not `0`).
- `-` accepted only at caret 0, only once; rejected mid-number and when
  one already leads.
- Letters / `.` / `+` / space silently ignored, **caret does not move**
  (assert `@field.caret` stayed put — the drift regression).
- Backspacing to empty ⇒ `value` goes to `nil`, not `0`.
- `value = 42` ⇒ buffer `"42"`, caret at end; `value = nil` ⇒ empty.
- `on_value_change` receives an `Integer`/`nil`, **never** a `String`;
  fires once per real value change; **no** fire on `"07"→"007"`.
- `text`/`text=`/`caret`/`on_change` are **not** on IntegerField's public
  surface.
- Focus lands in the inner field (caret visible); width truncation still
  applies (inherited by the child).

## Graduation (when implemented + stable)

Note several learnings here are *taxonomy* changes bigger than IntegerField
itself — make sure they graduate even though they touch shared files.

- **invariant-half → AGENTS.md** (update the `Input values (HasValue)`
  section, don't just append):
  - `HasValue` is now the **input-field mixin** — value seam **plus** a
    `focusable? = true` default (overridable). It is no longer "value
    only." `tab_stop?` is deliberately *not* in the mixin: it diverges
    (leaf field `true`; composing wrapper inherits `Component`'s `false`).
  - `TextInput` is renamed **`AbstractStringField`** and is *String-valued
    only* — the base of `TextField`/`TextArea`.
  - A typed input (IntegerField) **composes** an `AbstractStringField`
    rather than subclassing it, so its face carries only the typed `value`
    seam, never the widget's `text`/String-`value`. The
    `AbstractStringField#text=` seam-fire is correct precisely because it's
    only used where `value == text`.
  - The composed-wrapper shell (`children`/`cursor_position`/`on_focus`→
    field/`rect=`) is **duplicated** between IntegerField and ComboBox by
    choice — no base class; extract only if a 3rd composed field proves the
    pattern (non-breaking then).
- **reader-half → book**: into the eventual "values & the input seam"
  note — IntegerField is the clean worked example of "value is a derived
  parse of the buffer, and the widget is composed not inherited."
- **decision-half → DECISIONS.md**: extend `D-has-value` (or add
  `D-integer-field`) with — compose-not-inherit because inheriting
  `TextField` leaks a wrong-typed seam; `TextInput → AbstractStringField`
  rename + String-only scoping; `HasValue` reframed to the input-field
  mixin (focus defaults folded in); converter stays private/non-generic;
  empty is per-component (`nil`); `AbstractComposedField` considered and
  rejected as machinery for a 5-line shell. Then retire this note.
