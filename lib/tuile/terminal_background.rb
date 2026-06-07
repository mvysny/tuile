# frozen_string_literal: true

module Tuile
  # Detects whether the terminal background is light or dark, so {Screen}
  # can pick {Theme::LIGHT} or {Theme::DARK} automatically at startup.
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
  #    only when OSC 11 yields nothing.
  #
  # **Timing matters**: the OSC 11 reply arrives on stdin, so the query
  # must complete before {EventQueue#start_key_thread} owns stdin —
  # otherwise the reply bytes get consumed as garbage keystrokes. {Screen}
  # calls {.detect} from its constructor, which apps run before
  # {Screen#run_event_loop}; don't call this after the event loop started.
  module TerminalBackground
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

    class << self
      # Detects the terminal background. Queries OSC 11 when both `input`
      # and `output` are TTYs, falling back to `COLORFGBG`.
      #
      # @param input [IO] where the OSC 11 reply arrives (the TTY input).
      # @param output [IO] where the query is written (the TTY output).
      # @param env [Hash{String => String}] environment for the `COLORFGBG`
      #   fallback; defaults to `ENV` (which duck-types the `[]` lookup).
      # @param timeout [Numeric] max seconds to wait for the OSC 11 reply.
      # @return [Symbol, nil] `:light`, `:dark`, or nil when undetectable.
      def detect(input: $stdin, output: $stdout, env: ENV, timeout: QUERY_TIMEOUT)
        osc = query_osc11(input, output, timeout) if input.tty? && output.tty?
        osc || from_colorfgbg(env["COLORFGBG"])
      end

      private

      # Writes the OSC 11 query and classifies the reply. The whole
      # exchange runs with `input` in raw mode: the reply has no trailing
      # newline, so a canonical-mode read would block past the timeout,
      # and echo would smear the reply bytes onto the screen.
      # @param input [IO]
      # @param output [IO]
      # @param timeout [Numeric]
      # @return [Symbol, nil]
      def query_osc11(input, output, timeout)
        reply = input.raw do
          output.write(QUERY)
          output.flush
          read_reply(input, timeout)
        end
        match = REPLY.match(reply)
        match && classify(match.captures)
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

      # Relative luminance of the reported background, scaled per
      # component hex width (xterm replies 4 digits per channel, others 2).
      # @param components [Array<String>] three hex strings.
      # @return [Symbol] `:light` or `:dark`.
      def classify(components)
        r, g, b = components.map { |c| c.to_i(16).fdiv((16**c.length) - 1) }
        luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
        luminance > 0.5 ? :light : :dark
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
