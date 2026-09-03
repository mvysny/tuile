#!/usr/bin/env ruby
# frozen_string_literal: true

# Covers probe.rb's byte decoder. Deliberately NOT under spec/ — this is
# research tooling for ideas/hover.md, not gem code, so it must stay out of
# `rake spec` and out of CI. Plain assertions, no rspec:
#
#   ruby ideas/hover/probe_spec.rb
#
# Run it before an interactive probe session: a decode slip wastes the whole
# run, and one already happened (X10 coordinates are byte-33, not byte-32 —
# the offset differs from the button code's because coordinates are 1-based).

require_relative "probe"

FAILURES = []

def check(input, want)
  events, leftover = parse(input.dup)
  got = events.map { |kind, detail| "#{kind}: #{detail}" }
  if got == want && leftover.empty?
    puts "  ok    #{input.inspect}"
  else
    FAILURES << input
    puts "  FAIL  #{input.inspect}\n        got  #{got.inspect} leftover=#{leftover.inspect}\n        want #{want.inspect}"
  end
end

# A fragment must be held for the next read, never half-consumed: real reads
# do not align to event boundaries (measured: 4 reads in one 10s sample came
# back at 11.5 bytes/event, i.e. one event split across two reads).
def check_held(fragment)
  events, leftover = parse(fragment.dup)
  if events.empty? && leftover == fragment
    puts "  ok    held #{fragment.inspect}"
  else
    FAILURES << fragment
    puts "  FAIL  #{fragment.inspect} -> #{events.inspect} leftover=#{leftover.inspect}"
  end
end

puts "X10 encoding (button code is byte-32; coordinates are byte-33):"
check "\e[M !\"", ["x10: code=0 left at 0,1"]
check "\e[M#!!", ["x10: code=3 release at 0,0"]
check "\e[M\"!!", ["x10: code=2 right at 0,0"]
check "\e[M!!!", ["x10: code=1 middle at 0,0"]
check "\e[M`!!", ["x10: code=64 wheel_up at 0,0"]
check "\e[Ma!!", ["x10: code=65 wheel_down at 0,0"]
check "\e[M0!!", ["x10: code=16 left +ctrl at 0,0"]
puts "X10 motion codes — the set that arrives under 1002/1003:"
check "\e[M@!!", ["x10: code=32 MOTION left at 0,0"]      # drag; all of 1002's traffic
check "\e[MC!!", ["x10: code=35 MOTION release at 0,0"]   # hover; 1003 only
puts "X10 burst — two reports back to back must split cleanly (a fixed 6-byte"
puts "read is safe here, which is why a PTY spec may burst X10 but not SGR):"
check "\e[M !\"\e[M#!\"", ["x10: code=0 left at 0,1", "x10: code=3 release at 0,1"]

puts "SGR 1006 — press/release told apart by the final byte, and the release"
puts "carries its button (X10's release code 3 is anonymous):"
check "\e[<0;1;1M", ["sgr: code=0 left [press] at 0,0"]
check "\e[<0;1;1m", ["sgr: code=0 left [release] at 0,0"]
check "\e[<2;300;40m", ["sgr: code=2 right [release] at 299,39"]
check "\e[<35;11;6M", ["sgr: code=35 MOTION release [press] at 10,5"]
check "\e[<64;5;5M", ["sgr: code=64 wheel_up [press] at 4,4"]
puts "SGR past the X10 cap — the whole reason to request 1006:"
check "\e[<0;500;9M", ["sgr: code=0 left [press] at 499,8"]

puts "focus tracking (mode 1004) and DECRQM replies:"
check "\e[I", ["focus: FocusIn"]
check "\e[O", ["focus: FocusOut"]
check "\e[?1003;2$y", ["decrpm: mode 1003 => reset (supported)"]
check "\e[?1005;0$y", ["decrpm: mode 1005 => NOT RECOGNIZED"]

puts "partial input is held, not consumed:"
["\e[M", "\e[M!", "\e[<0;1", "\e[?100"].each { check_held(_1) }

puts
if FAILURES.empty?
  puts "ALL PARSER TESTS PASS"
else
  puts "#{FAILURES.size} FAILED"
end
exit(FAILURES.empty? ? 0 : 1)
