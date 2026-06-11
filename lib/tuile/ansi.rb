# frozen_string_literal: true

module Tuile
  # ANSI escape sequence constants. Tuile emits colors and text attributes
  # via {StyledString} / {Color}, which produce **SGR** sequences ("Select
  # Graphic Rendition", `ESC [ <params> m` — e.g. `\e[31m` red, `\e[1m`
  # bold, `\e[0m` reset). Host apps may also use Rainbow, which emits the
  # same form.
  module Ansi
    # SGR reset (`ESC [ 0 m`). Restores the terminal's default foreground,
    # background, and text attributes.
    # @return [String]
    RESET = "\e[0m"

    # Begin Synchronized Update (DEC private mode 2026, "Synchronized
    # Output"). The terminal stops refreshing its display and buffers every
    # subsequent write until {SYNC_END}, then composites the whole batch
    # atomically — so a multi-cell repaint is never shown half-drawn. This is
    # what stops flicker when a frame redraws a large region (e.g. the
    # full-scene repaint a shrinking popup forces). Terminals without support
    # ignore the private-mode set, so it's a safe no-op there. {Screen#repaint}
    # wraps its single frame-buffer flush in this pair.
    # @return [String]
    SYNC_BEGIN = "\e[?2026h"

    # End Synchronized Update — see {SYNC_BEGIN}. Releases the buffered frame
    # and lets the terminal repaint.
    # @return [String]
    SYNC_END = "\e[?2026l"
  end
end
