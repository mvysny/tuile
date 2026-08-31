# frozen_string_literal: true

# Benchmark for {Tuile::Color#quantize}, which {Tuile::Buffer#flush} applies to
# every color it emits on a terminal below `:truecolor`.
#
# The question it answers is whether that wants a cache in front of it. Two
# workloads bracket the answer: a *typical* app cycling a handful of colors
# (where any cache hits every time) and a *gradient* streaming distinct RGB
# values — what a Component::LogTextView gets when it ingests a tool's colored
# output, and the input an unbounded memo grows without limit on.
# See DECISIONS.md D_color_depth.
#
#   ruby -Ilib benchmark/quantize.rb   # or: bundle exec rake benchmark

require "tuile"
require "benchmark"

N = 1_000_000

memo = {}
lru = {}
LRU_MAX = 256

def key_for(color) = color.value.then { |(r, g, b)| (r << 16) | (g << 8) | b }

typical = Array.new(8) { Tuile::Color.rgb(rand(256), rand(256), rand(256)) }
typical_stream = Array.new(N) { |i| typical[i % 8] }
gradient = Array.new(100_000) { |v| Tuile::Color.rgb((v >> 9) & 0xff, (v >> 4) & 0xff, (v << 1) & 0xff) }
gradient_stream = Array.new(N) { |i| gradient[i % gradient.size] }

puts "ruby #{RUBY_VERSION}, #{N} quantize calls per row, depth :palette256"

{ "typical (8 colors)" => typical_stream, "gradient (100k colors)" => gradient_stream }.each do |label, stream|
  memo.clear
  lru.clear
  puts "\n#{label}:"
  Benchmark.bm(9) do |bm|
    bm.report("compute") { stream.each { _1.quantize(:palette256) } }
    bm.report("memo") { stream.each { |c| memo[key_for(c)] ||= c.quantize(:palette256) } }
    bm.report("lru256") do
      stream.each do |c|
        k = key_for(c)
        if (hit = lru.delete(k))
          lru[k] = hit # reinsert: Ruby Hashes are insertion-ordered, so this is recency
        else
          lru.shift if lru.size >= LRU_MAX
          lru[k] = c.quantize(:palette256)
        end
      end
    end
  end
  puts "  memo entries: #{memo.size}, lru entries: #{lru.size}"
end

# The ceiling a bare quantizer can hit: every cell of a 160x50 grid a distinct
# RGB on both fg and bg. Tuile repaints on events, not at 60 fps.
worst = gradient.first(160 * 50 * 2)
elapsed = Benchmark.realtime { 100.times { worst.each { _1.quantize(:palette256) } } }
puts format("\nworst-case quantizing (%<n>d computes): %<ms>.3f ms", n: worst.size, ms: elapsed * 10)

# What it costs where it actually runs. Buffer#quantized_style is called per
# dirty *cell*, so the row memo — one remembered answer, since a painted run
# shares one frozen Style — is what keeps a depth below :truecolor off the
# repaint's critical path. Drop it and the RGB rows below triple.
WIDTH = 160
HEIGHT = 50
REPEATS = 200

def repaint_ms(depth, first, second)
  buffer = Tuile::Buffer.new(Tuile::Size.new(WIDTH, HEIGHT), color_depth: depth)
  rows = [first, second].map do |style|
    Tuile::StyledString.new([Tuile::StyledString::Span.new(text: "x" * WIDTH, style: style)])
  end
  buffer.flush # drain the initial fully-dirty grid
  elapsed = Benchmark.realtime do
    REPEATS.times do |k|
      # Alternate so every repaint really diffs, and the graphemes differ too.
      row = rows[k % 2]
      HEIGHT.times { |y| buffer.set_text(0, y, row) }
      buffer.set_char(0, 0, k.even? ? "a" : "b")
      buffer.flush
    end
  end
  elapsed * 1000 / REPEATS
end

def styles(first, second) = [Tuile::StyledString::Style.new(fg: first), Tuile::StyledString::Style.new(fg: second)]

named = styles(Tuile::Color::RED, Tuile::Color::BLUE)
rgb = styles(Tuile::Color.rgb(30, 30, 34), Tuile::Color.rgb(31, 31, 35))

puts "\nFull-screen repaint (#{WIDTH}x#{HEIGHT}), ms per alternating repaint:"
{ "named  truecolor" => [:truecolor, named], "named  palette256" => [:palette256, named],
  "rgb    truecolor" => [:truecolor, rgb], "rgb    palette256" => [:palette256, rgb],
  "rgb    ansi16" => [:ansi16, rgb] }.each do |label, (depth, pair)|
  puts format("  %<label>-18s %<ms>.3f ms", label: label, ms: repaint_ms(depth, *pair))
end
