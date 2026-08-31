# frozen_string_literal: true

module Tuile
  # How many colors the terminal on the other end can actually show — the
  # depth {Color#quantize} degrades a color to:
  #
  #   ColorDepth.detect                                        # => :truecolor
  #   ColorDepth.detect(env: { "TERM" => "xterm-256color" })   # => :palette256
  #   ColorDepth.detect(env: {})                               # => :ansi16
  #
  # Env-only: no terminal round-trip, so unlike {TerminalBackground.detect}
  # there is no stdin timing to respect, and the answer cannot go stale
  # mid-session the way a background color can.
  #
  # Terminals lie in both directions — `COLORTERM` frequently doesn't survive
  # ssh (it isn't in the default `SendEnv` set) or tmux — so {OVERRIDE_ENV}
  # beats every other signal, the escape hatch for a terminal detected wrong.
  # Misdetection otherwise lands *conservatively*: a truecolor tmux
  # advertising only `tmux-256color` reads as `:palette256`, which renders
  # coarser but never mangled.
  #
  # == Implementation details
  #
  # Terminfo is deliberately not consulted — its `RGB` boolean and
  # `colors#0x1000000` would mean shelling out to `tput`/`infocmp` at every
  # startup, and the env ladder plus the override already covers the real
  # terminal matrix.
  module ColorDepth
    # The depths, most capable first: 24-bit RGB, the 256-color palette, and
    # the 16 named ANSI colors.
    # @return [Array<Symbol>]
    DEPTHS = %i[truecolor palette256 ansi16].freeze

    # Environment variable that overrides detection outright; holds one of
    # {DEPTHS}. Empty counts as unset.
    # @return [String]
    OVERRIDE_ENV = "TUILE_COLOR_DEPTH"

    # `COLORTERM` values that promise 24-bit color.
    # @return [Array<String>]
    TRUECOLOR_COLORTERM = %w[truecolor 24bit].freeze

    class << self
      # The terminal's color depth, from {OVERRIDE_ENV}, else `COLORTERM`,
      # else `TERM` (a `-direct` entry means 24-bit, a `256color` one the
      # palette), else the 16-color floor.
      #
      # @param env [Hash{String => String}] environment to read; defaults to
      #   `ENV` (which duck-types the `[]` lookup).
      # @return [Symbol] one of {DEPTHS}.
      # @raise [ArgumentError] when {OVERRIDE_ENV} holds an unknown value. It
      #   is only ever set deliberately, so a typo in it is worth failing at
      #   startup over — ignoring it silently means a whole session of
      #   debugging the wrong colors.
      def detect(env: ENV)
        override = env[OVERRIDE_ENV].to_s
        return parse_override(override) unless override.empty?

        term = env["TERM"].to_s
        return :truecolor if TRUECOLOR_COLORTERM.include?(env["COLORTERM"].to_s.downcase) ||
                             term.include?("-direct")
        return :palette256 if term.include?("256color")

        :ansi16
      end

      private

      # @param value [String] the raw {OVERRIDE_ENV} value.
      # @return [Symbol]
      def parse_override(value)
        depth = value.strip.downcase.to_sym
        return depth if DEPTHS.include?(depth)

        raise ArgumentError,
              "invalid #{OVERRIDE_ENV}: #{value.inspect} (expected one of #{DEPTHS.join(", ")})"
      end
    end
  end
end
