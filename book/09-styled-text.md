# 9. Styled text

Everything Tuile draws is, eventually, text with colors on it — a
highlighted list row, a red error label, a border in the active accent.
The value type that carries "text plus styling" through the whole
framework is {Tuile::StyledString}, and it's worth one chapter of *why*,
because the obvious representation — a plain `String` with ANSI escape
codes threaded through it — is the one Tuile deliberately does *not* use.

## Why not just a String with escape codes in it

A terminal styles text with SGR escape sequences: `"\e[31mred\e[0m"` is
the word "red" in red. It's tempting to treat a styled string as exactly
that — a normal `String` that happens to contain those bytes — and let
the terminal sort it out.

The trouble shows up the moment you do anything *structural* to the text.
Slice out columns 5 through 10: which colors are active at column 5? To
answer, you have to scan every escape sequence from the start of the
string, tracking the running SGR state, because the color at column 5 was
set by some `\e[...m` that might be twenty characters earlier. Word-wrap
it across a narrow viewport: every break point needs that same running
state re-established on the next line, or the color bleeds or resets
wrong. Concatenate two of them: whose reset wins? Every operation becomes
"parse the SGR state machine, figure out what's active here, splice
carefully." The escape codes and the text are tangled together, and the
tangle has to be re-untangled on every edit.

{Tuile::StyledString} untangles it once, structurally. A styled string is
a sequence of **spans**, each a maximal run of characters that share one
complete {Tuile::StyledString::Style} — foreground, background, bold,
italic, underline, strikethrough. The spans are non-overlapping and tile
the whole string: every character belongs to exactly one span, and that
span's `style` *is* the character's style. There are no overlay layers to
merge, no running state to reconstruct. "What's the style at column 5?"
is just "which span contains column 5?" — a lookup, not a replay.

That's the trade. You pay one extra type — you construct or parse a
{Tuile::StyledString} instead of building a raw `String` — and in return
slicing, wrapping, and concatenation become ordinary operations on a list
of spans, each of which already knows its own style. For a framework that
slices and wraps text constantly, on every repaint, that's the right side
of the trade.

## The algebra

Once text is spans, the operations you'd want on a string come back, but
style-aware. You concatenate with `+` (a plain `String` operand is parsed
first, so embedded escapes round-trip). You take substrings by *display
column* with `slice` — display column, not byte offset, because a
fullwidth CJK character is two columns wide and a combining mark is zero,
and the terminal cares about columns. You split on newlines with `lines`,
word-wrap to a width with `wrap`, and truncate-with-ellipsis with
`ellipsize`. Every one of them returns a fresh {Tuile::StyledString} with
the spans carried across the cut intact — the value is immutable and its
spans are frozen and shared, so these are cheap.

Two details are worth knowing because they're choices, not accidents.
Slicing **never splits a wide character**: if a two-column glyph straddles
the boundary of your slice, it's dropped rather than rendered as half a
character, which the terminal couldn't do anyway. And wrapping guarantees
no output line exceeds the target width *whenever every character fits in
that width* — a single glyph wider than the whole viewport still lands on
its own line at its natural width, because there's nowhere narrower to put
it. The exact signatures live in the rdoc; this is the shape of the
toolbox.

## Rendering and the minimal diff

Two spans, both red, sitting next to each other, should not each re-emit
`\e[31m` — the terminal is already red. {Tuile::StyledString#to_ansi}
renders the spans to escape codes by **diffing** each span's style against
the one before it, emitting only the codes that actually changed. A
transition back to the plain default style emits a single `\e[0m` rather
than laboriously turning each attribute off. The rendered run always
closes with `\e[0m` if it ended non-default, so styling never bleeds into
whatever the terminal prints next.

This isn't just tidiness. The same style-diffing logic
({Tuile::StyledString::Style#sgr_to}) is what the back buffer uses when it
flushes changed cells to the terminal (chapter 2) — cell-to-cell there,
span-to-span here, identical minimal sequences. Styled text and the
flicker-free repaint model are the same idea at two scales: never rewrite
what's already correct.

## The parser: strict by default, lenient on request

You can go the other way too — parse an ANSI-coded `String` *into* spans
with {Tuile::StyledString.parse}. Here Tuile makes a sharp choice that's
easy to get wrong, so it's worth stating plainly: **the parser is strict
by default.**

Strict means it recognizes exactly the SGR codes that map to a
{Tuile::StyledString::Style}'s attributes — the foreground and background
colors, bold, italic, underline, strikethrough — and *raises* on anything
else. An unmodeled attribute like blink or reverse video, an unknown SGR
code, a non-SGR escape like a cursor move or an OSC sequence: all of them
are a {Tuile::StyledString::ParseError}, not a shrug. The reason is a
contract worth protecting: `parse(to_ansi(x)) == x`. If parsing silently
dropped what it didn't understand, that round-trip would quietly lie, and
a styled string that survived a save/load cycle might come back subtly
different. Strict parsing keeps the round-trip honest — anything the model
can't represent is refused at the door, not swallowed.

But strictness is wrong for one common job: piping in colored output you
didn't produce and don't control — `git --color` through a pager, a build
tool's output, anything that sprinkles cursor moves and exotic attributes
you have no intention of modeling. For that, pass `lenient: true`. Now the
parser keeps the colors and attributes it understands and **discards
everything else** — unmodeled codes, malformed extended colors, cursor
moves, OSC and other string sequences, stray escapes — instead of
raising. It's lossy by definition (`parse(x, lenient: true)` does not
round-trip back to `x`), and that's the point: "give me the colors, throw
the rest away." Strict for text you own and must preserve exactly; lenient
for text you're borrowing and only want the colors from.

---

{Tuile::StyledString} is the quiet primitive under everything visible.
You rarely construct one by hand for simple cases — a {Tuile::Component::Label}
takes a plain `String` and wraps it for you — but the moment you render
your own content with per-span colors (a log line, a syntax-highlighted
snippet, a diff), this is the type you're building, and the theming hook
from chapter 6 is where you rebuild it when the palette changes.
