# frozen_string_literal: true

module Tuile
  # Detects the terminal's background color — both the light/dark scheme
  # {Screen} picks {Theme::LIGHT} or {Theme::DARK} from, and, when the
  # terminal answers the query, the actual RGB behind it.
  #
  # Two mechanisms, in order of reliability:
  #
  # 1. **OSC 11 query** — writes `ESC ] 11 ; ? BEL` to the terminal; modern
  #    terminals (xterm, kitty, alacritty, wezterm, iTerm2, GNOME Terminal,
  #    Windows Terminal) reply on stdin with the background color
  #    (`\e]11;rgb:RRRR/GGGG/BBBB` + BEL or ST). The color's relative
  #    luminance against a 0.5 threshold decides light vs dark. Terminals
  #    that don't support the query simply never reply, so the read is
  #    bounded by a short timeout.
  # 2. **`COLORFGBG` env var** — rxvt/konsole export `"fg;bg"` ANSI palette
  #    indices. Less reliable (stale across SSH/tmux, often unset); used
  #    only when OSC 11 yields nothing. Palette indices carry no RGB, so
  #    this path fills in {Result#scheme} and leaves {Result#color} nil.
  #
  # **Timing matters**: the OSC 11 reply arrives on stdin, so the query
  # must complete before {EventQueue#start_key_thread} owns stdin —
  # otherwise the reply bytes get consumed as garbage keystrokes. {Screen}
  # calls {.detect} from its constructor, which apps run before
  # {Screen#run_event_loop}; don't call this after the event loop started.
  #
  # Once the loop *is* running the query is still available, from the other
  # side: {Screen} writes {QUERY} on every OS appearance flip and the key
  # thread — which owns stdin by then — reads the reply back through
  # {Keys.getkey} and {.parse}. See {Screen#background_color}.
  module TerminalBackground
    # What a detection found: the light/dark `scheme`, and the background
    # `color` when a terminal actually reported one.
    #
    # `color` is nil whenever the scheme came from the `COLORFGBG`
    # fallback, so a consumer deriving a tint from the background must
    # handle nil — plenty of terminals answer neither query.
    #
    # @!attribute [r] scheme
    #   @return [Symbol] `:light` or `:dark`.
    # @!attribute [r] color
    #   @return [Color, nil] the reported background as 24-bit RGB, or nil
    #     when only `COLORFGBG` answered.
    Result = Data.define(:scheme, :color)

    # How long to wait for the OSC 11 reply. Generous for a local
    # terminal; bounded so unsupporting terminals (which never reply)
    # don't stall startup.
    # @return [Float] seconds.
    QUERY_TIMEOUT = 0.1

    # The OSC 11 background-color query, BEL-terminated.
    # @return [String]
    QUERY = "\e]11;?\a"

    # Matches the OSC 11 reply. Components are 1–4 hex digits each
    # (terminals vary); `rgba:` (4 components) also matches — the alpha
    # tail is ignored.
    # @return [Regexp]
    REPLY = %r{\e\]11;rgba?:(\h{1,4})/(\h{1,4})/(\h{1,4})}

    # Enables mode 2031: the terminal pushes a color-scheme report
    # (`\e[?997;1n` dark / `\e[?997;2n` light) whenever the OS appearance
    # flips — see {EventQueue::ColorSchemeEvent}. Terminals without
    # support ignore the sequence. Written by {Screen#run_event_loop}.
    # @return [String]
    NOTIFY_ON = "\e[?2031h"

    # Disables mode 2031 again; written when the event loop exits.
    # @return [String]
    NOTIFY_OFF = "\e[?2031l"

    class << self
      # Detects the terminal background. Queries OSC 11 when both `input`
      # and `output` are TTYs, falling back to `COLORFGBG`.
      #
      #   TerminalBackground.detect
      #   # => #<data Result scheme=:dark, color=#<Tuile::Color [30, 30, 46]>>
      #
      # @param input [IO] where the OSC 11 reply arrives (the TTY input).
      # @param output [IO] where the query is written (the TTY output).
      # @param env [Hash{String => String}] environment for the `COLORFGBG`
      #   fallback; defaults to `ENV` (which duck-types the `[]` lookup).
      # @param timeout [Numeric] max seconds to wait for the OSC 11 reply.
      # @return [Result, nil] nil when the background is undetectable —
      #   neither mechanism answered.
      def detect(input: $stdin, output: $stdout, env: ENV, timeout: QUERY_TIMEOUT)
        osc = query_osc11(input, output, timeout) if input.tty? && output.tty?
        return osc if osc

        scheme = from_colorfgbg(env["COLORFGBG"])
        scheme && Result.new(scheme: scheme, color: nil)
      end

      # Parses an OSC 11 reply — the terminal's answer to {QUERY}, matched
      # anywhere in `reply`.
      #
      #   TerminalBackground.parse("\e]11;rgb:1e1e/1e1e/2e2e\a").color
      #   # => #<Tuile::Color [30, 30, 46]>
      #
      # Public because a reply also arrives *mid-session*, long after
      # {.detect}'s own bounded read: once the key thread owns stdin, a
      # whole reply surfaces as one "key" from {Keys.getkey}.
      #
      # @param reply [String] raw terminal output that may contain a reply.
      # @return [Result, nil] nil when `reply` holds no OSC 11 reply.
      def parse(reply)
        match = REPLY.match(reply)
        return nil unless match

        # Components arrive as 1–4 hex digits (terminals vary), so each is
        # scaled by its own width: "ab" and "abab" are both ~0.67.
        components = match.captures.map { |c| c.to_i(16).fdiv((16**c.length) - 1) }
        Result.new(scheme: classify(components), color: to_color(components))
      end

      private

      # Writes the OSC 11 query and parses the reply. The whole exchange
      # runs with `input` in raw mode: the reply has no trailing newline,
      # so a canonical-mode read would block past the timeout, and echo
      # would smear the reply bytes onto the screen.
      # @param input [IO]
      # @param output [IO]
      # @param timeout [Numeric]
      # @return [Result, nil]
      def query_osc11(input, output, timeout)
        reply = input.raw do
          output.write(QUERY)
          output.flush
          read_reply(input, timeout)
        end
        parse(reply)
      rescue SystemCallError, IOError
        nil
      end

      # Accumulates reply bytes until a BEL/ST terminator or the deadline.
      # Terminals that don't support OSC 11 never reply — returning
      # whatever arrived (usually nothing) lets the caller fail soft.
      # @param input [IO]
      # @param timeout [Numeric]
      # @return [String]
      def read_reply(input, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        buffer = +""
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return buffer if remaining <= 0 || IO.select([input], nil, nil, remaining).nil?

          buffer << input.readpartial(256)
          return buffer if buffer.include?("\a") || buffer.include?("\e\\")
        end
      rescue EOFError
        buffer
      end

      # Light or dark, by relative luminance against a 0.5 threshold.
      # @param components [Array<Float>] red, green and blue, each 0.0..1.0.
      # @return [Symbol] `:light` or `:dark`.
      def classify(components)
        r, g, b = components
        luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
        luminance > 0.5 ? :light : :dark
      end

      # The reported background as a 24-bit {Color}. Quantizing xterm's
      # 16-bit-per-channel reply down to 8 loses nothing a terminal can
      # display, and keeps the exposed value in the type the rest of Tuile
      # paints with.
      # @param components [Array<Float>] red, green and blue, each 0.0..1.0.
      # @return [Color]
      def to_color(components)
        Color.rgb(*components.map { (_1 * 255).round })
      end

      # `COLORFGBG` is `"fg;bg"` (rxvt sometimes `"fg;default;bg"`) with
      # ANSI palette indices. White-ish backgrounds — 7 (white) and the
      # bright range 9–15 — read as light; 0–6 and 8 as dark; anything
      # else (missing, `"default"`, out of range) is inconclusive.
      # @param value [String, nil]
      # @return [Symbol, nil]
      def from_colorfgbg(value)
        bg = value&.split(";")&.last
        return nil unless bg&.match?(/\A\d+\z/)

        case bg.to_i
        when 0..6, 8 then :dark
        when 7, 9..15 then :light
        end
      end
    end
  end
end
