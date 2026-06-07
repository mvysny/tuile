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
  end
end
