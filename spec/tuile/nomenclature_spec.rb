# frozen_string_literal: true

module Tuile
  RSpec.describe "nomenclature" do
    # Each of these named a *terminal row* with the wrong noun — or, like
    # `display_row`, named no coordinate system at all. None has a legitimate
    # use left after the 0.12.0 sweep, which is the only reason a grep can
    # police them: the guard holds no allowlist, so a hit is a regression
    # rather than a judgement call, and a rename that needs an exception here
    # is evidence the rename is wrong.
    #
    # `line_count` is deliberately absent — {Component::TextView::Region#line_count}
    # counts `\n` units and is correct. A word that is right in one space and
    # wrong in another belongs in design/terminology.md, not in a grep.
    banned = %w[
      set_line draw_line top_line physical_line hard_line display_row
      screen_row viewport_lines
    ].freeze

    it "lib/ calls a terminal row a row, never a line" do
      lib = File.expand_path("../../lib", __dir__)
      offenders = Dir["#{lib}/**/*.rb"].sort.flat_map do |path|
        File.readlines(path).each_with_index.filter_map do |text, i|
          hit = banned.find { text.include?(_1) }
          "#{path.delete_prefix("#{lib}/")}:#{i + 1}: #{hit}" if hit
        end
      end

      assert_empty offenders,
                   "banned nomenclature in lib/ — see design/terminology.md:\n  #{offenders.join("\n  ")}"
    end

    # The `on_` prefix is reserved for the event families — a hook or a listener
    # slot — so a traversal or a predicate must not take it. These three carried
    # it as the *preposition* ("on the tree", "on the loop thread") until they
    # were renamed; like the row/line list above, none has a legitimate use
    # left, which is what lets a grep police them with no allowlist.
    reserved = %w[on_tree on_shown_tree on_loop_thread].freeze

    it "keeps the on_ prefix for events, not for walks or predicates" do
      lib = File.expand_path("../../lib", __dir__)
      offenders = Dir["#{lib}/**/*.rb"].sort.flat_map do |path|
        File.readlines(path).each_with_index.filter_map do |text, i|
          hit = reserved.find { text.match?(/\b#{_1}\b/) }
          "#{path.delete_prefix("#{lib}/")}:#{i + 1}: #{hit}" if hit
        end
      end

      assert_empty offenders,
                   "the on_ prefix is reserved for hooks and listener slots; " \
                   "a walk is walk_*, a predicate in_*:\n  #{offenders.join("\n  ")}"
    end
  end
end
