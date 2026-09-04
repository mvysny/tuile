# 10. Locale: the conventions, not the words

Chapter 6 told one story about adapting to the user's environment: the
terminal reports whether it is light or dark, Tuile picks a matching
{Tuile::Theme}, and the whole UI restyles. This chapter tells the same
story about a different fact — not what the terminal looks like, but how
the *person* in front of it expects a date and a number to be spelled.

The two are shaped alike on purpose. A frozen value type, detected once
at startup, held on the screen, read at use time, replaceable at
runtime, with a hook for anything that baked the old answer in. If you
have read chapter 6, you already know the shape; what is worth your time
here is the *boundary* — because this is the feature most likely to grow
into something Tuile is not.

## The one rule: conventions, never prose

> A {Tuile::Locale} holds formatting conventions — how a value is
> rendered and parsed. It never holds prose.

That sentence is the whole design. It is what makes `Locale` a bag of
about eight members rather than an internationalization subsystem, and
it is the test a ninth member has to pass.

The distinction is easy to feel once you see the two halves side by
side. "Dates in this session are spelled `dd.mm.yyyy`" is a convention:
it is a *rule* about rendering, it applies to every date the app will
ever show, and Tuile can obey it without knowing anything about your
app. "The date you typed is not valid" is prose: it is one sentence, in
one language, that belongs to one widget, and translating it is a job
with a catalogue, interpolation, and pluralization behind it. Tuile does
the first and stays out of the second — a component's wording stays the
component's own, settable where it matters.

And the line is not Tuile's invention. POSIX drew it first: `LC_MESSAGES`
carries the language your programs speak, `LC_TIME` and `LC_NUMERIC`
carry the formatting conventions. Tuile reads the formatting categories
and never the message one. That is why a session can coherently ask for
an English UI *and* ISO dates *and* a decimal comma — three categories,
three independent answers, which is exactly what one of your author's
machines is configured to want.

## What is in one

```ruby
locale = Tuile::Screen.instance.locale

locale.date_formats        # => ["%Y-%m-%d"]   strftime patterns, primary first
locale.calendar_start      # => Date::GREGORIAN
locale.first_weekday       # => 1              Monday, in Date#wday numbering
locale.month_names[9]      # => "September"
locale.abbr_day_names[1]   # => "Mon"
locale.decimal_separator   # => "."
```

Two things about those last few are worth pausing on.

**The name tables are keyed by the `Date` accessor that reads them.**
`month_names[date.month]`, `day_names[date.wday]` — so you never do
arithmetic to look a name up. That is why the two have different shapes:
`Date#month` is 1-based, so the month tables are `Hash`es keyed `1..12`;
`Date#wday` is 0-based, so the day tables are plain seven-element
arrays. It looks like an inconsistency and is the opposite of one. A
0-based month array would answer `month_names[9] # => "October"` — a
*plausible wrong answer*, silently, in the calendar header of a
month-view someone ships. The `Hash` makes that mistake impossible to
express instead of merely documented against.

**`date_formats` is a list, and the first entry is special.** Parsing
tries them in order and the first whole match wins; the primary —
`formats.first` — is also what gets *written* when a value is assigned or
a loosely typed buffer is canonicalized. Lenient in, strict out. Which
means only the primary has to survive a round-trip; a later entry only
ever parses, so it is allowed to be lossy. Chapter 7 has the field-side
story; {Tuile::Component::DateField} has the details.

## Detection: ask the system, and only when it was asked

Ruby exposes no locale data at all. There is no `nl_langinfo` binding,
nothing on `Date`, nothing in `Etc`; `Date::MONTHNAMES` is frozen
English under every `LC_ALL` you set, and `strftime("%x")` is a fixed
American `%m/%d/%y` that merely *looks* like a locale channel. So
{Tuile::Locale.system} shells out to `locale -k` — one subprocess of
about a millisecond, whose answers are already strftime patterns, which
is Tuile's own vocabulary rather than a second grammar to translate.

The interesting part is not the subprocess. It is the gate in front of
it.

The C/POSIX default date format is American. That means "the user said
nothing" and "the user wants `%m/%d/%y`" are *indistinguishable* from
the answer — so a container with no `LANG` set would confidently show
American dates to a Norwegian. Tuile therefore detects only when the
environment actually said something: if the POSIX chain for a category
is empty, or names `C` or `POSIX`, the probe's answer for that category
is thrown away and {Tuile::Locale::ISO} stands.

And the gate is *per category*, which is the part that surprises people.
Gating once on "any locale variable is set" is wrong on a real machine:
a session exporting only `LC_NUMERIC=de_DE.UTF-8` would open the gate,
and then `d_fmt` — resolving through an unset `LC_TIME` and an unset
`LANG` — comes back American. So the date conventions are kept only if
`LC_ALL` / `LC_TIME` / `LANG` speaks, and the numeric one only if
`LC_ALL` / `LC_NUMERIC` / `LANG` does. One subprocess, two gates.

Everything else about detection is defensive, because none of it can be
allowed to fail loudly at startup: `locale(1)`'s exit status is useless
in both directions (a bad locale name exits 0 and quietly returns C; an
unknown keyword exits 1 while printing every good key), so the status is
ignored and each value is validated on its own. Anything that does not
hold up falls back to its `ISO` member individually — not
all-or-nothing. A missing binary, a Windows box, a musl container: `ISO`,
no exception raised.

## The floor is ISO 8601, and that is an argument

{Tuile::Locale::ISO} is the only constant Tuile ships. There is no
`EN_US`, no `DE`, and there will not be: two presets are a catalogue, a
catalogue implies completeness, and completeness is a promise about the
world's date conventions that a TUI toolkit has no business making. You
build your own from `ISO`:

```ruby
screen.locale = Tuile::Locale::ISO.with(date_formats: ["%d.%m.%Y", "%Y-%m-%d"])
```

Every member is validated in the constructor, and `Data#with` re-runs the
constructor — so an invalid `Locale` is unreachable by either route.

`ISO` is a defensible floor rather than a default someone picked, because
three of its members cite the same standard: ISO 8601 dates, an ISO 8601
week starting Monday, and the proleptic Gregorian calendar ISO 8601
mandates. The names are Ruby's own frozen English tables, re-keyed but
not authored — so Tuile ships zero locale data of its own, even in the
fallback. And the decimal separator is `"."` not because ISO says so (ISO
31-0 rather prefers the comma) but because `Float#to_s` writes a dot and
a field's `value=` goes through it: any other floor would make a numeric
field disagree with itself before you configured anything.

## Fields follow the session unless you say otherwise

A {Tuile::Component::DateField} takes both of its conventions from
`Screen#locale` until you assign them. So the common cases are one line
each, and they compose:

```ruby
screen.locale = Locale::ISO.with(date_formats: ["%d.%m.%Y"])  # every field
field.formats = "%Y-%m-%d"                                    # this one only
field.formats = nil                                           # follow again
```

`nil` restoring inheritance is the same shape `placeholder=` and
`bg_color=` already use, and it is what keeps the two decisions
independent: overriding one field is not opting it out of the session
forever.

## When the locale changes under you

{Tuile::Screen#locale=} fires {Tuile::Component#on_locale_changed}
across the attached tree and then invalidates all of it — the same
machinery {Tuile::Screen#theme=} uses, for the same reason.

Because everything repaints, anything your code *pulls* at paint or parse
time needs no hook at all. A date field parses its buffer on read; a
calendar grid would look month names up while painting. Both simply come
out right on the next frame.

The hook is for state you *pushed* somewhere when you last read the
conventions. A date field's typing hint is the worked example: it lives
in its editor's `placeholder`, written when the formats were last set, so
a repaint alone would faithfully repaint the stale `dd.mm.yyyy`. The
field overrides `on_locale_changed` to re-derive it — and, while it is
there, to rewrite a buffer that still parses into the new primary format.
Your own code does the same for a date you rendered into a
{Tuile::Component::Label}, either by overriding the hook or by assigning
the listener:

```ruby
label.on_locale_changed = -> { label.text = due.strftime(screen.locale.date_formats.first) }
```

One consequence to accept rather than defend against: a field holding a
half-typed buffer when the grammar changes under it may stop parsing, and
will then read as bad input. That is correct — the text is still there,
the user can see it, and they can fix it. A locale change is a
once-a-session event, not something worth contorting a field to survive.

The other rule inherited from chapter 6 applies unchanged: **read the
locale at use time; never cache it in an ivar.** A cached one strands on
the old conventions the moment someone assigns a new locale, and nothing
raises to tell you.
