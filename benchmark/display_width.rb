# frozen_string_literal: true

# Benchmark for the display-width hot path behind {Tuile::Buffer} painting.
#
# `Unicode::DisplayWidth.of` is sub-microsecond but called once per grapheme
# while painting, so it dominates a full-screen repaint. {Tuile::Buffer}
# memoizes it ({Buffer.display_width}) and measures each grapheme exactly once
# per paint; this script quantifies both the raw call and the end-to-end win.
#
#   ruby -Ilib benchmark/display_width.rb   # or: bundle exec rake benchmark

require "tuile"
require "benchmark"

SAMPLES = {
  "ASCII '-'" => "-",
  "ASCII 'a'" => "a",
  "box '─'" => "─",
  "arrow '↓'" => "↓",
  "CJK '世'" => "世",
  "emoji 🎈" => "\u{1F388}"
}.freeze

WIDTH = 160
HEIGHT = 50
N = 1_000_000

puts "ruby #{RUBY_VERSION}, unicode-display_width #{Unicode::DisplayWidth::VERSION}"
puts

puts "Per-call width lookup (#{N} calls each): raw gem vs memoized Buffer.display_width"
Benchmark.bm(26) do |bm|
  SAMPLES.each do |label, g|
    Tuile::Buffer.display_width(g) # warm the memo
    bm.report("#{label} raw")  { N.times { Unicode::DisplayWidth.of(g) } }
    bm.report("#{label} memo") { N.times { Tuile::Buffer.display_width(g) } }
  end
end
puts

# A representative VM-list row: state glyph, name, balloon + direction, and a
# long box-drawing rule — exactly the content the balloon bug came from.
row = Tuile::StyledString.parse("▶ Flow \u{1F388}↓ #{"─" * 140}")
rows = Array.new(HEIGHT) { row }

buffer = Tuile::Buffer.new(Tuile::Size.new(WIDTH, HEIGHT))
HEIGHT.times { |y| buffer.set_line(0, y, rows[y]) }
buffer.flush # drain the initial fully-dirty grid

# Alternate two contents so every repaint actually diffs and flushes.
alt = Tuile::StyledString.parse("▶ flow \u{1F388}↑ #{"━" * 140}")
alts = Array.new(HEIGHT) { alt }
reps = 1000

puts "Full-screen repaint (#{WIDTH}x#{HEIGHT}), #{reps} alternating repaints:"
elapsed = Benchmark.realtime do
  reps.times do |k|
    src = k.even? ? alts : rows
    HEIGHT.times { |y| buffer.set_line(0, y, src[y]) }
    buffer.flush
  end
end
puts format("  %<total>.1f ms total => %<each>.3f ms/repaint (%<rate>.0f repaints/sec)",
            total: elapsed * 1000, each: elapsed * 1000 / reps, rate: reps / elapsed)
