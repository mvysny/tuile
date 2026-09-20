# frozen_string_literal: true

# Benchmark for what a clip costs, split into the two halves that are priced
# separately — the question `design/ideas/universal-clip.md` turns on.
#
# 1. **Per write.** {Tuile::Canvas}'s three draw helpers branch on `@clip.nil?`.
#    Measured against a clip that *contains* every write, which is the case
#    universal clipping would hit almost always: the arithmetic runs, nothing
#    is cut.
# 2. **Per component.** {Tuile::Component#effective_clip} folds every ancestor's
#    `clip_rect` once per component per repaint, inside {Tuile::Screen#canvas_for}.
#    Measured at a realistic depth, with no ancestor declaring one (today) and
#    with every ancestor declaring one (universal).
#
# The object counts matter more than the microseconds: the fold allocates a
# `Point` and two `Rect`s per level, all immediately garbage, against zero today.
#
#   ruby -Ilib benchmark/clip.rb   # or: bundle exec rake benchmark

require "tuile"
require "benchmark"

DEPTH = 7
WRITE_N = 20_000
FOLD_N = 300_000

# A component imposing no clip — today's default, the baseline.
class Plain < Tuile::Component; end

# A component clipping descendants to its own rect — what "universal" would
# make the default.
class Clipping < Tuile::Component
  def clip_rect = Tuile::Rect.new(0, 0, rect.width, rect.height)
end

# @param klass [Class] the component class every node in the chain gets.
# @return [Tuile::Component] the deepest child of a freshly built chain.
def build(klass)
  root = klass.new
  root.rect = Tuile::Rect.new(0, 0, 120, 40)
  node = root
  DEPTH.times do
    child = klass.new
    node.__send__(:add_child, child)
    child.rect = Tuile::Rect.new(1, 1, 100, 30)
    node = child
  end
  node
end

# @param label [String] printed as-is.
# @param iterations [Integer] timed calls, after a warmup the timer never sees.
# @return [Float] seconds per operation.
def bench(label, iterations, &block)
  200.times(&block)
  elapsed = Benchmark.realtime { iterations.times(&block) }
  puts format("  %<label>-32s %<total>8.2f ms  %<each>8.3f us/op",
              label:, total: elapsed * 1000, each: elapsed * 1_000_000 / iterations)
  elapsed / iterations
end

# @return [Float] objects allocated per call, GC held off so the count is exact.
def allocations(&block)
  block.call
  GC.disable
  before = GC.stat(:total_allocated_objects)
  100.times(&block)
  count = GC.stat(:total_allocated_objects) - before
  GC.enable
  count / 100.0
end

buffer = Tuile::Buffer.new(Tuile::Size.new(120, 40))
row = Tuile::StyledString.parse("a fairly ordinary row of list content ~40c")
whole = Tuile::Rect.new(0, 0, 120, 40)
unclipped = Tuile::Canvas.new(buffer, origin: Tuile::Point::ZERO, clip: nil)
contained = Tuile::Canvas.new(buffer, origin: Tuile::Point::ZERO, clip: whole)

puts "ruby #{RUBY_VERSION}"
puts
puts "Per write — #{WRITE_N} ops, clip contains every write (nothing is cut):"
puts "  set_text, 40 rows per op (a full-screen text repaint)"
nil_text = bench("clip = nil", WRITE_N) { 40.times { |r| unclipped.set_text(0, r, row) } }
clip_text = bench("clip = whole screen", WRITE_N) { 40.times { |r| contained.set_text(0, r, row) } }
puts format("  => clipped is %<ratio>.2fx", ratio: clip_text / nil_text)

puts "  fill, whole screen per op"
nil_fill = bench("clip = nil", WRITE_N) { unclipped.fill(whole) }
clip_fill = bench("clip = whole screen", WRITE_N) { contained.fill(whole) }
puts format("  => clipped is %<ratio>.2fx", ratio: clip_fill / nil_fill)
puts

# What write_clipped_text adds per set_text, to see whether it is the cost.
bench("StyledString#display_width", WRITE_N * 40) { row.display_width }
puts

puts "Per component — effective_clip at depth #{DEPTH}, #{FOLD_N} ops:"
plain = build(Plain)
clipping = build(Clipping)
no_clip = bench("no ancestor declares (today)", FOLD_N) { plain.__send__(:effective_clip) }
all_clip = bench("every ancestor declares", FOLD_N) { clipping.__send__(:effective_clip) }
puts format("  => %<ratio>.2fx, +%<delta>.3f us per component per paint",
            ratio: all_clip / no_clip, delta: (all_clip - no_clip) * 1_000_000)
puts format("  objects allocated: %<today>.1f today, %<universal>.1f universal",
            today: allocations { plain.__send__(:effective_clip) },
            universal: allocations { clipping.__send__(:effective_clip) })
