# frozen_string_literal: true

# Benchmark for what clipping costs, split into the two halves that are priced
# separately — the question `design/ideas/universal-clip.md` turns on.
#
# 1. **Per write.** {Tuile::Canvas}'s three draw helpers branch on `@clip.nil?`.
#    Measured against a clip that *contains* every write, which is the case
#    almost every paint hits: the arithmetic runs, nothing is cut.
# 2. **Per component.** {Tuile::Screen#clip_for} folds the component's own rect
#    with every ancestor's, once per component per repaint, inside
#    {Tuile::Screen#canvas_for}. Measured against tree depth, since that is what
#    it is linear in, and beside the `nil` fast path the opt-in design used to
#    take — the baseline universal clipping gave up.
#
# The object counts matter as much as the microseconds: the fold allocates a
# `Point` and two `Rect`s per level, all immediately garbage.
#
#   ruby -Ilib benchmark/clip.rb   # or: bundle exec rake benchmark

require "tuile"
require "benchmark"

DEPTHS = [1, 3, 7, 15].freeze
WRITE_N = 20_000
FOLD_N = 200_000

# @param depth [Integer] how many components sit between the pane and the leaf.
# @return [Tuile::Component] the deepest child of a freshly built chain.
def build(depth)
  root = Tuile::Component::Layout::Absolute.new
  Tuile::Screen.instance.content = root
  root.rect = Tuile::Rect.new(0, 0, 120, 40)
  node = root
  depth.times do
    child = Tuile::Component::Layout::Absolute.new
    node.add(child)
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

Tuile::Screen.fake

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

# What a clipped set_text adds per call, to see whether it is the cost.
bench("StyledString#display_width", WRITE_N * 40) { row.display_width }
puts

puts "Per component — Screen#clip_for, #{FOLD_N} ops, by tree depth:"
screen = Tuile::Screen.instance
DEPTHS.each do |depth|
  leaf = build(depth)
  each = bench("depth #{depth}", FOLD_N) { screen.clip_for(leaf) }
  puts format("    %<objects>.0f objects/call, %<ns>.0f ns per level",
              objects: allocations { screen.clip_for(leaf) }, ns: each * 1_000_000_000 / (depth + 1))
end
puts
puts "  For scale: the `nil` fast path the opt-in design took was ~0.4 us and 0 objects,"
puts "  and a Label painting one row costs roughly #{format("%.0f", nil_text * 1_000_000 / 40)} us."

Tuile::Screen.close
