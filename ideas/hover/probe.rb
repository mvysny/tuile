#!/usr/bin/env ruby
# frozen_string_literal: true

# Terminal mouse-mode probe — fills one row of `ideas/hover.md`'s matrix.
# Research tooling for that idea; it dies with the note at graduation.
#
# Deliberately depends on nothing but stdlib: this measures the *terminal*, so
# Tuile's own parsing (and its fixed 5-byte escape gulp) must stay out of the
# way. Bytes are read greedily and parsed incrementally, so the log shows what
# actually arrived rather than what a fixed-width reader would have made of it.
#
# Run it in its OWN terminal / tmux window — never in one where another TUI
# owns stdin, and never in the terminal a coding agent is drawing on: mode 1003
# would pour motion reports into *its* stdin.
#
#   ruby ideas/hover/probe.rb [logfile]
#
# Rows recorded so far live in `ideas/hover.md` under "Measured". Still wanted:
# Alacritty bare, Alacritty over ssh, tmux local. The logs themselves are not
# committed — a re-run regenerates them, and the findings are what graduate.
#
# The parser is covered by ideas/hover/probe_spec.rb — run that before trusting
# an interactive session, since a decode slip wastes the whole run (it already
# caught an X10 coordinate off-by-one: the button code is byte-32, but the
# coordinates are 1-based *and* offset, so they decode as byte-33).

require "io/console"

LOG = if __FILE__ == $PROGRAM_NAME
        File.open(ARGV[0] || "mouse_probe.log", "w").tap { _1.sync = true }
      else
        $stderr # loaded for testing: never open a log, never touch the terminal
      end

def say(msg) = ($stdout.print("#{msg}\r\n"); $stdout.flush)
def log(msg) = LOG.puts(msg)
def esc(seq) = ($stdout.print(seq); $stdout.flush)

def both(msg)
  say msg
  log msg
end

# --- incremental parser -----------------------------------------------------
# Returns [events, leftover]. Each event is [kind, detail].
def parse(buf)
  events = []
  until buf.empty?
    if buf.start_with?("\e[M")
      break if buf.bytesize < 6

      # Button code is offset by 32; coordinates are 1-based *and* offset by 32,
      # so they come back with -33. Mixing these up is the classic X10 slip.
      cb, cx, cy = buf[3].ord - 32, buf[4].ord - 33, buf[5].ord - 33
      events << [:x10, decode_cb(cb) + " at #{cx},#{cy}"]
      buf = buf[6..]
    elsif (m = buf.match(/\A\e\[<(\d+);(\d+);(\d+)([Mm])/))
      cb = m[1].to_i
      kind = m[4] == "M" ? "press" : "release"
      events << [:sgr, "#{decode_cb(cb)} [#{kind}] at #{m[2].to_i - 1},#{m[3].to_i - 1}"]
      buf = buf[m[0].bytesize..]
    elsif buf.start_with?("\e[I")
      events << [:focus, "FocusIn"]
      buf = buf[3..]
    elsif buf.start_with?("\e[O")
      events << [:focus, "FocusOut"]
      buf = buf[3..]
    elsif (m = buf.match(/\A\e\[\?(\d+);(\d+)\$y/))
      events << [:decrpm, "mode #{m[1]} => #{decrpm_meaning(m[2].to_i)}"]
      buf = buf[m[0].bytesize..]
    elsif buf.start_with?("\e[<") || buf.start_with?("\e[?")
      break # incomplete, wait for more bytes
    else
      events << [:other, buf[0].inspect]
      buf = buf[1..]
    end
  end
  [events, buf]
end

def decode_cb(code)
  base = code & 0b11
  mods = []
  mods << "shift" if code & 4 != 0
  mods << "meta"  if code & 8 != 0
  mods << "ctrl"  if code & 16 != 0
  motion = code & 32 != 0
  wheel  = code & 64 != 0
  name =
    if wheel
      %w[wheel_up wheel_down wheel_left wheel_right][base] || "wheel?#{base}"
    else
      %w[left middle right release][base]
    end
  "code=#{code} #{motion ? 'MOTION ' : ''}#{name}#{mods.empty? ? '' : " +#{mods.join('+')}"}"
end

def decrpm_meaning(ps)
  { 0 => "NOT RECOGNIZED", 1 => "set", 2 => "reset (supported)",
    3 => "permanently set", 4 => "permanently reset" }[ps] || "unknown(#{ps})"
end

# --- drain ------------------------------------------------------------------
# Reads for `seconds`, returning every parsed event. `stop_on` ends it early.
def drain(seconds, stop_on: nil)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  buf = +""
  out = []
  loop do
    left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    break if left <= 0
    next unless IO.select([$stdin], nil, nil, [left, 0.2].min)

    chunk = $stdin.read_nonblock(4096)
    # Timestamp the *read*, and record the chunk size: inter-arrival gaps and
    # multi-event chunks are how we tell whether ssh/tmux coalesced anything.
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    buf << chunk
    events, buf = parse(buf)
    log format("  [read %+7.3fs %3dB -> %d ev]", now - deadline + seconds, chunk.bytesize, events.size) if events.any?
    events.each do |kind, detail|
      out << [kind, detail]
      log "    #{kind}: #{detail}"
    end
    break if stop_on && buf.empty? && out.any? { |(_, d)| d.include?(stop_on) }
  end
  out
end

def wait_for_enter
  say "    [press ENTER to start]"
  loop do
    IO.select([$stdin], nil, nil, 60) or break
    break if $stdin.read_nonblock(4096).include?("\r") || false
  rescue IO::WaitReadable, EOFError
    break
  end
end

ALL_OFF = "\e[?1000l\e[?1002l\e[?1003l\e[?1004l\e[?1006l"

return unless __FILE__ == $PROGRAM_NAME

begin
  $stdin.raw do
    log "=== mouse probe #{Time.now.iso8601 rescue Time.now} ==="
    log "TERM=#{ENV['TERM']} COLORTERM=#{ENV['COLORTERM']} TMUX=#{ENV['TMUX']}"
    log "size=#{IO.console.winsize.reverse.join('x')}"
    log ""

    # -- Phase 0: DECRQM support ---------------------------------------------
    both "PHASE 0  DECRQM mode-support probe (no mouse needed)"
    [9, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 1016].each do |mode|
      esc "\e[?#{mode}$p"
      got = drain(0.3)
      both "  #{mode}: #{got.empty? ? 'NO REPLY' : got.map(&:last).join(', ')}"
    end
    log ""

    # -- Phase 1: 1000 + X10 -------------------------------------------------
    both ""
    both "PHASE 1  mode 1000, X10 encoding — click a few times (5s)"
    wait_for_enter
    esc "\e[?1000h"
    got = drain(5)
    esc "\e[?1000l"
    both "  => #{got.size} events; releases seen: #{got.count { |(_, d)| d.include?('release') }}"
    log ""

    # -- Phase 2: 1000 + SGR 1006 -------------------------------------------
    both ""
    both "PHASE 2  mode 1000 + SGR 1006 — click a few times, incl. right-click (5s)"
    wait_for_enter
    esc "\e[?1006h\e[?1000h"
    got = drain(5)
    esc "\e[?1000l"
    sgr = got.count { |(k, _)| k == :sgr }
    both "  => #{got.size} events, #{sgr} in SGR form (0 means 1006 was ignored)"
    log ""

    # -- Phase 3: 1002 -------------------------------------------------------
    both ""
    both "PHASE 3  mode 1002 — FIRST move with no button (expect nothing),"
    both "         THEN drag with the left button held (expect motion) (8s)"
    wait_for_enter
    esc "\e[?1002h"
    got = drain(8)
    esc "\e[?1002l"
    motion = got.count { |(_, d)| d.include?("MOTION") }
    both "  => #{got.size} events, #{motion} motion"
    log ""

    # -- Phase 4: 1003 rate --------------------------------------------------
    both ""
    both "PHASE 4  mode 1003 — move the mouse around normally, NON-STOP (10s)"
    wait_for_enter
    esc "\e[?1003h"
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    got = drain(10)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    esc "\e[?1003l"
    motion = got.count { |(_, d)| d.include?("MOTION") }
    both format("  => %d events (%d motion) in %.1fs = %.1f/s  <-- THE NUMBER",
                got.size, motion, elapsed, got.size / elapsed)
    log ""

    # -- Phase 5: pointer leaves the window ---------------------------------
    both ""
    both "PHASE 5  mode 1003 + 1004 — move the pointer OUT of this window,"
    both "         click another app, then come back (10s)"
    wait_for_enter
    esc "\e[?1003h\e[?1004h"
    got = drain(10)
    esc "\e[?1003l\e[?1004l"
    focus = got.select { |(k, _)| k == :focus }
    both "  => #{got.size} events; focus events: #{focus.empty? ? 'NONE' : focus.map(&:last).join(', ')}"
    both "     (NONE means nothing tells us the pointer left — hover would strand)"
    log ""

    # -- Phase 6: wide coordinates ------------------------------------------
    cols = IO.console.winsize[1]
    both ""
    if cols > 223
      both "PHASE 6  mode 1003 + 1006 — click PAST column 223 (width=#{cols}) (8s)"
      wait_for_enter
      esc "\e[?1006h\e[?1003h"
      got = drain(8)
      esc "\e[?1003l\e[?1006l"
      both "  => #{got.size} events; max x seen: #{got.map { |(_, d)| d[/at (\d+),/, 1].to_i }.max}"
    else
      both "PHASE 6  SKIPPED — terminal is #{cols} cols, need >223 to test the X10 cap"
      log "PHASE 6 skipped: width #{cols}"
    end

    both ""
    both "done — log written to #{LOG.path}"
  end
ensure
  esc ALL_OFF
  LOG.close
end
