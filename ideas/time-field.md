# `TimeField` — build brief

**Status:** design settled 2026-09-05; nothing built. Every *why* — the value-type
argument, the toolkit survey, the roads not taken, the re-grow rules — is in
`DECISIONS.md` **`D_time_field`**, and every ruling this brief does not restate is
inherited from **`D_date_field`**. This file is the *what*, in build order. If a
step below looks wrong, argue it against the `D_` entry, not here. Retire this
file when the field ships; the `D_` entry's `Status:` line flips at the same time.

Findings marked **verified** were run in this repo's Ruby (`ruby -rdate`).

## Read first

- `lib/tuile/component/date_field.rb`, in full. It is the template — copy it,
  don't inherit from it (the second copy of the date-field shell, as
  `FloatField` is of the numeric one).
- `lib/tuile/locale.rb`: `Locale::DateFormats` (`REF`, `HINTS`, `DIRECTIVE`,
  `each_directive`, `LOCALE_LOOKALIKES`, `widen`, `round_trips?`),
  `date_formats_from`, `from_keywords`, `KEYWORDS`.
- `D_time_field`, `D_date_field`, `D_locale`.

## Step 0 — verify before writing code

Both are ruled either way; the check decides one constant and one sentence.

1. **The epoch.** `gem install activerecord`, then
   `ActiveModel::Type::Time.new.cast("13:45")` — confirm the dummy date is
   `2000-01-01`. If yes, `MIDNIGHT = Time.utc(2000, 1, 1)` and the rdoc says
   "matches Rails". If no, use Rails' date anyway; only the constant changes.
2. **`%p` leniency.** In this Ruby:
   `Date._strptime("1:45pm", "%I:%M %p")`, `"1:45 PM"`, `"1:45PM"`. Whatever
   parses, parses; whatever doesn't costs one rdoc sentence beside the
   "`%p` is fixed English" limitation. **Do not** derive a spaceless secondary
   to compensate.

## Step 1 — hoist the lexer (own commit, `Breaking:`)

Move `DIRECTIVE`, `each_directive` and `LOCALE_LOOKALIKES` from
`Locale::DateFormats` into a new `Locale::Formats` module. `DateFormats` keeps
its public name and API (`REF`, `HINTS`, `widen`, `round_trips?`) as a validator
*over* the shared lexer. Date specs stay green; nothing else changes in this
commit. CHANGELOG gets a `**Breaking:**` line naming the three moved constants.

## Step 2 — `Locale#time_formats`

The ninth member. Validated like `date_formats`, carrying the locale's spelling
at **full detected precision** — the field strips, not the locale.

- `Locale::ISO` gets `time_formats: ["%H:%M:%S"]`.
- `KEYWORDS` gains `t_fmt`. **Not** `t_fmt_ampm`, **not** `am_pm`.
- `Locale.system`'s existing `LC_TIME` gate covers it — no new category.
- Detected list = `[expand(t_fmt), "%H:%M:%S"].uniq`, each entry validated,
  failures dropped (the probe has nobody to tell). Expansion table:
  `%T` → `%H:%M:%S`, `%R` → `%H:%M`, `%r` → `%I:%M:%S %p`. Expansion is
  normalization and belongs here; the seconds strip is **not** done here.
- **No rule that an entry must contain `%S`.** `Locale.new(time_formats: ["%H:%M"])`
  is legal.

**Verified** against the locales generated on this box:

| locale | `t_fmt` | `Locale#time_formats` |
|---|---|---|
| en_US | `%r` | `["%I:%M:%S %p", "%H:%M:%S"]` |
| en_GB | `%T` | `["%H:%M:%S"]` |
| fi_FI | `%H.%M.%S` | `["%H.%M.%S", "%H:%M:%S"]` |
| C | `%H:%M:%S` | `["%H:%M:%S"]` |

### `Locale::TimeFormats` — the validator

A sibling of `DateFormats` over the hoisted lexer. No `widen`.

- `REF = Time.utc(2000, 1, 1, 13, 45, 0)`. Round-trip: `strptime(REF.strftime(f), f)`
  rebuilt on the epoch `== REF`. Properties that matter: hour ≥ 13 (so `%I`
  without `%p` fails), minute ≠ hour, second = 0 (so a minute primary passes).
- **Verified** pass: `%H:%M`, `%H:%M:%S`, `%T`, `%R`, `%r`, `%H.%M`, `%Hh%M`,
  `%H%M`, `%k:%M`, `%I:%M %p`, `%I.%M %p`, `%I:%M%P`.
- **Verified** reject: `%I:%M`, `%I:%M:%S`, `%l:%M`, `%p`, `%H`, `%M:%S`, `%s`,
  any `%-H`.
- **Rejected by name**, each with a message saying why: `%x` `%X` `%c` (locale
  lookalikes — shared list); **zone** `%z` `%Z` `%:z` `%::z` `%s` ("this field
  holds no zone"); **sub-second** `%L` `%N` ("a time of day holds whole seconds").
  All of these *round-trip cleanly*, which is why they need naming.
- `HINTS`: `%H` `%I` `%k` `%l` → `hh`, `%M` → `mm`, `%S` → `ss`, `%p` → `AM`,
  `%P` → `am`, `%%` → `%`. Separate table from `DateFormats::HINTS`; any
  directive outside it ⇒ `nil` hint (derive exactly or not at all).

Specs: drive detection through `Locale.from_keywords` with canned `t_fmt`
answers for the four rows above; `FakeScreen` keeps pinning `Locale::ISO`.

## Step 3 — `TimeField` skeleton

`Component::TimeField < AbstractWrappingField`, `include HasBadInput`. A
`TextField` editor passed to `super`; no `extent`, no paint code of its own.

- `MIDNIGHT` — public frozen `Time`, the epoch (Step 0 decides the date).
- `TimeField.at(hour, minute, second = 0)` → `Time.utc(MIDNIGHT.year, …)`,
  **through the range gate of Step 4** — `at(24, 0)` raises `ArgumentError`.
- `empty_value = nil`; `MAX_TEXT_LENGTH = 64`;
  `bad_input_message = "not a valid time".freeze`.
- `step` — `Integer` seconds, default `60`, set in `initialize`.
  `step=` raises `ArgumentError` unless `Integer` and `1 <= step < 86400`.
  No `nil`, no `Float`/`Rational`.
- `value` — derived from the buffer on every read (Step 4). Never cached.
- `value=(v)` — `nil` clears; anything responding to `hour`/`min`/`sec` is
  rebuilt as `Time.utc(epoch…, v.hour, v.min, v.sec)` (sub-seconds dropped) and
  written into the buffer in `formats.first`; a `Date` or a `String` raises
  `TypeError`.
- `formats` — **reader only**, no writer (Step 5). rdoc: "a report, not a
  request; deliberately no writer", the `Component#size` wording.

## Step 4 — the parse, with a third gate

For each format in `formats`, in order:

1. `Date._strptime(text, format)` — `nil` or a non-empty `:leftover` ⇒ no match.
2. **Range gate:** `hour` in `0..23`, `min` in `0..59`, `sec` (default 0) in
   `0..59`, else no match. Needed because `Time` normalizes where `Date` raised
   (**verified**): `Date._strptime("24:00", "%H:%M")` ⇒ `{hour: 24, min: 0}` and
   `Time.utc(2000,1,1,24,0,0)` is *the next day*; `"13:45:60"` parses and
   `Time.utc(…,13,45,60)` is `13:46:00`.
3. `Time.utc(epoch…, hour, min, sec)` — construction, not validation.

First match wins. `Date._strptime` already rejects over-wide fields (`"25:00"`,
`"13:99"` ⇒ `nil`, **verified**) and accepts unpadded `"1:45"` under `%H:%M`.
`24:00` is rejected — one rdoc sentence: legal ISO end-of-day, unrepresentable
in `Time`. **No `require "time"`**; `Time.strptime` is not used.

One private range check, two callers (`at` and the parse).

## Step 5 — `formats`, derived from `locale.time_formats` and `step`

```
strip(f)  = f with "%S" and the literal run immediately before it removed
            ("%I:%M:%S %p" → "%I:%M %p", "%H%M%S" → "%H%M"); a format with no
            "%S" is returned unchanged
full      = locale.time_formats
stripped  = full.map { strip(_1) }.uniq
formats   = step < 60 ? (full + stripped).uniq : stripped
```

Fallback: if `step < 60` and no entry of `full` contains `%S`, prepend
`"%H:%M:%S"`. Never splice a separator to add one.

`locale` is `Component#locale` (answers `Locale::ISO` with no `Screen`), read on
every call — never stored.

| locale | `formats` at `step >= 60` (default) | writes | `formats` at `step < 60` | writes |
|---|---|---|---|---|
| en_US | `["%I:%M %p", "%H:%M"]` | `01:45 PM` | `["%I:%M:%S %p", "%H:%M:%S", "%I:%M %p", "%H:%M"]` | `01:45:00 PM` |
| en_GB | `["%H:%M"]` | `13:45` | `["%H:%M:%S", "%H:%M"]` | `13:45:00` |
| fi_FI | `["%H.%M", "%H:%M"]` | `13.45` | `["%H.%M.%S", "%H:%M:%S", "%H.%M", "%H:%M"]` | `13.45.00` |
| C | `["%H:%M"]` | `13:45` | `["%H:%M:%S", "%H:%M"]` | `13:45:00` |

The asymmetry is deliberate: at `step < 60` typing `13:45` must parse (lossless
widening to `13:45:00`); at `step >= 60` typing `13:45:30` must be bad input
(lossy). Both are specced.

## Step 6 — stepping

Up/Down claim the editor's `on_key_up` / `on_key_down` slots (as `DateField`).

- Parse the buffer. If it parses: add/subtract `step` seconds, wrap modulo
  86400, write back in `formats.first`. **Add, never snap** — `step = 900` from
  `13:07` gives `13:22`.
- If empty or unparseable: write **now** — `Time.now` truncated to the field's
  precision (seconds zeroed at `step >= 60`), on the epoch. Lands *on* now, not
  now ± 1. Yes, this clobbers a half-typed `13:4`; that is `DateField`'s ruling,
  shared — change both fields together or neither.
- `23:59` + 60 → `00:00`; `00:00` − 60 → `23:59`; `11:59 AM` + 60 → `12:00 PM`
  (arithmetic on the `Time`, nothing special).

PageUp/PageDown: not in v1.

## Step 7 — placeholder, commit, latch (copied verbatim)

- Placeholder derived from `formats.first` through `TimeFormats::HINTS`, exactly
  or `nil`. en_US default ⇒ `hh:mm AM`; fi_FI ⇒ `hh.mm`; ISO ⇒ `hh:mm`.
- `commit` on blur and ENTER rewrites a parsing buffer in `formats.first`
  (`1:45` → `01:45`; at `step < 60`, `13:45` → `13:45:00`).
- `bad_input_settled?` latched to the commit gestures, cleared by
  `on_editor_change` — copy `DateField`'s mechanism including the two ordering
  details its rdoc names (settle *after* the rewrite; settling invalidates).

## Step 8 — `on_locale_changed` and `step=` are one path

Both mean "the format list changed under a buffer". One private method:

1. Re-derive the placeholder.
2. If the buffer parses under the *new* `formats`, rewrite it in the new
   `formats.first`. If it does not, leave it — it is now bad input; `value`
   reads `nil`.
3. If `value` changed (including to `nil`), fire `on_value_change`.

`on_locale_changed` calls it (protected, `super` first). `step=` validates,
stores, then calls it. Specs: widening `60 → 1` rewrites `13:45` → `13:45:00`
with no value change; narrowing `1 → 60` over `13:45:30` leaves the buffer,
`bad_input?` is true, `value` is nil, `on_value_change` fired once.

## Step 9 — specs (`spec/tuile/component/time_field_spec.rb` + `locale_spec.rb`)

Beyond mirroring `date_field_spec`:

- `at(24, 0)`, `at(13, 60)`, `at(13, 45, 60)` raise; parse of `"24:00"` and
  `"13:45:60"` is bad input, not a value on the wrong date.
- `value=` accepts `Time`, `DateTime`, a `Time` subclass; `Date` and `String`
  raise `TypeError`; `Time.now` with nsec truncates.
- `step=` domain: `0`, `-1`, `86400`, `1.5`, `nil` raise; `7` and `90` accepted.
- Both `formats` tables above, under `Locale.from_keywords` canned locales.
- `formats` follows a `screen.locale=` reassignment (no snapshot).
- Add-never-snap; wrap both directions; step from empty lands on now with
  seconds zeroed at the default step.
- Step 8's two scenarios.
- Screen-free: `TimeField.new.formats == ["%H:%M"]` with no `Screen`.
- Whatever Step 0.2 found about `1:45pm`, pinned as a spec either way.
- Contract suite: add `TimeField` to `component_contract_spec`'s catalog.

## Step 10 — registrations

- rdoc on the class, `step=` (the `< 60` rule, the two named costs from
  `D_time_field`), `formats` (a report; no writer), `value=` (what it accepts,
  the year-2000 warning), `MIDNIGHT`, `.at`.
- `D_time_field` `Status:` → implemented; `D_date_field` already points at it.
- CHANGELOG: `Add Component::TimeField …`, `Add Locale#time_formats …`,
  `**Breaking:** Locale::Formats hoist …`.
- `README.md` Components row beside `DateField`; `AGENTS.md` layout list
  (`time_field.rb`, and `locale.rb`'s line gains `time formats`).
- Book ch7 beside `DateField`; ch10 a paragraph on `time_formats` and one
  sentence on why the seconds strip is the field's.
- Sampler pane under Input → Typed: assign a canned fi_FI-shaped `Locale` to the
  pane's screen and show `step: 60` and `step: 1` side by side.
- `ideas/new-components.md`: strike `TimeField` out of the Tier 2 row the way
  `DateField` is struck out of Tier 1 (the picker stays Tier 2 as phase 2).
- `rake sig`; commit `sig/tuile.rbs`.
- Delete this file.

## Not in v1 (recorded in `D_time_field`)

Picker dropdown (phase 2; `step` already spaces its rows), PageUp/PageDown,
`LocalTimeField`, `DateTimeField` (`ideas/composite-field.md`).
