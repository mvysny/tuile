# frozen_string_literal: true

module Tuile
  class Component
    # A read-only viewer for prose: chunks of formatted text that scroll
    # vertically. Shape-wise a hybrid between {Label} (string-shaped content
    # via {#text=}) and {List} (scroll keys, optional scrollbar, auto-scroll).
    #
    # Text is modeled as a {StyledString}: embedded `\n` are hard line breaks,
    # lines wider than the viewport are word-wrapped via {StyledString#wrap}
    # (style spans are preserved across wrap boundaries — unlike the older
    # ANSI-as-bytes wrapping, color does *not* get dropped on continuation
    # rows). {#text=} accepts a {String} (parsed via {StyledString.parse},
    # so embedded ANSI is honored) or a {StyledString} directly; {#text}
    # always returns the {StyledString}.
    #
    # For incremental updates pick the right primitive: {#append} (aliased
    # as `<<`) is verbatim and stream-friendly — chunks are concatenated
    # straight onto the buffer, with embedded `\n` becoming hard breaks.
    # {#add_line} is the "log entry" convenience — it starts the content on
    # a fresh line by inserting a leading `\n` when the buffer is non-empty.
    # {#remove_last_n_lines} pops hard lines back off the tail — the
    # inverse of building up a region with {#append} / {#add_line}, so a
    # caller streaming reformattable content (e.g. partially-rendered
    # Markdown that may need to retract its last paragraph) can replace
    # the tail without rewriting the whole text. Turn on {#auto_scroll}
    # to keep the latest content in view.
    #
    # TextView is meant to be the content of a {Window} — focus indication and
    # keyboard-hint surfacing rely on the surrounding window chrome.
    class TextView < Component
      def initialize
        super
        # Three parallel structures, kept in lockstep by every mutator:
        # `@hard_lines` is the logical model (one entry per `\n`-delimited
        # line, width-independent); `@physical_lines` is the rendered view
        # (each hard line word-wrapped to `wrap_width` and padded with
        # trailing blanks, so painting a row is a lookup); and
        # `@hard_line_wrap_counts` is an Integer-per-hard-line cache of
        # how many physical rows each hard line occupies, so a mid-buffer
        # splice can find its starting physical-row offset without
        # re-wrapping every preceding hard line.
        #
        # Invariants:
        # - `@hard_line_wrap_counts.size == @hard_lines.size`
        # - `@hard_line_wrap_counts.sum == @physical_lines.size`
        # A full rebuild ({#rewrap}) happens on {#text=} and width changes;
        # other mutators splice incrementally.
        @hard_lines = []
        @physical_lines = []
        @hard_line_wrap_counts = []
        @text = StyledString::EMPTY
        @content_size = Size::ZERO
        @blank_line = StyledString::EMPTY
        @top_line = 0
        @auto_scroll = false
        @scrollbar_visibility = :gone
        # The view always has at least one region — an implicit default. It
        # owns whatever hard lines exist that no later region claims. App
        # code that never calls {#create_region} sees the same behavior as
        # before (a single region containing everything); apps that do call
        # {#create_region} stack additional regions at the spatial tail.
        @regions = [Region.send(:new, self)]
      end

      # @return [StyledString] the current text. Defaults to an empty
      #   {StyledString}. Internally the text is stored as an array of hard
      #   lines so {#append} can stay O(appended) instead of re-scanning the
      #   whole buffer; the joined {StyledString} returned here is
      #   reconstructed on first read after a mutation and cached, so
      #   repeated reads are O(1) but the first read after {#append} pays
      #   O(total spans).
      def text
        @text ||= build_text
      end

      # @return [Integer] index of the first visible physical line.
      attr_reader :top_line

      # @return [Symbol] `:gone` or `:visible`.
      attr_reader :scrollbar_visibility

      # @return [Boolean] if true, mutating the text scrolls the viewport so
      #   the last line stays in view. Default `false`.
      attr_reader :auto_scroll

      # Replaces the text. Embedded `\n` characters become hard line breaks.
      # A `String` is parsed via {StyledString.parse} (so embedded ANSI is
      # honored); a `StyledString` is used as-is; `nil` is coerced to an
      # empty {StyledString}.
      #
      # Detaches every existing {Region} (including the original default)
      # and installs a fresh internal default region that owns all the new
      # hard lines. Any handle the caller was holding becomes detached and
      # raises on use — see {Region#attached?}. The no-op short-circuit
      # (matching value, same {StyledString}) preserves existing regions.
      # @param value [String, StyledString, nil]
      # @return [void]
      def text=(value)
        new_text = StyledString.parse(value)
        content_unchanged = text == new_text

        # `text=` is a structural reset: even when the new content matches
        # the old, existing region handles must die — the caller said "set
        # the text," not "merge with what's there." The unchanged-content
        # path still skips the expensive rewrap / invalidate work.
        @text = new_text
        @hard_lines = new_text.empty? ? [] : new_text.lines
        @regions.each { |r| r.send(:detach!) }
        @regions = [Region.send(:new, self, @hard_lines.size)]
        return if content_unchanged

        @content_size = compute_content_size
        rewrap
        update_top_line_if_auto_scroll
        invalidate
      end

      # Creates a new empty {Region} at the spatial tail of the document
      # and returns its handle. Subsequent {#append} / {#<<} / {#add_line}
      # calls route through this new region (since it is now the spatial
      # tail). Earlier regions keep their content and their handles stay
      # valid; their {Region#range} shifts as later regions grow.
      #
      # Apps streaming logically-distinct sections (e.g. an LLM's "thinking"
      # vs. "assistant" output) create one region per section, hold the
      # handles, and call `region.append` / `region.text=` directly when
      # they need to grow or rewrite an earlier section.
      # @return [Region]
      def create_region
        region = Region.send(:new, self)
        @regions << region
        region
      end

      # @return [Boolean] true iff {#text} is empty (no hard lines).
      def empty? = @hard_lines.empty?

      # Appends `str` verbatim. Embedded `\n` characters become hard line
      # breaks; otherwise the text is concatenated onto the current last
      # hard line. Designed for streaming use (e.g. an LLM chat window
      # receiving partial messages — feed each chunk straight in). Accepts
      # the same input forms as {#text=}; empty/`nil` input is a no-op.
      #
      # For the "add an entry on a new line" pattern use {#add_line}.
      #
      # Cost is O(appended + width-of-current-last-hard-line) — the
      # previously last hard line is re-wrapped (because the extension may
      # cause it to wrap differently), any additional hard lines created by
      # embedded `\n` are wrapped fresh. The cached {#text} is invalidated
      # and rebuilt on demand.
      # @param str [String, StyledString, nil]
      # @return [void]
      def append(str)
        screen.check_locked
        appended = StyledString.parse(str)
        return if appended.empty?

        tail_region = @regions.last
        tail_was_empty = tail_region.empty?
        new_segments = appended.lines
        width = wrap_width

        if tail_was_empty
          # An empty spatial-tail region (either a fresh buffer, or an empty
          # region the app created at the tail) means new content starts on
          # a fresh hard line — we must not extend the previous region's
          # last line.
          new_segments.each { |hl| push_hard_line(hl, width) }
          added = new_segments.size
        else
          extension = new_segments.first
          unless extension.empty?
            old_last = pop_hard_line
            push_hard_line(old_last + extension, width)
          end
          new_segments[1..].each { |hl| push_hard_line(hl, width) }
          added = new_segments.size - 1
        end

        tail_region.send(:line_count=, tail_region.line_count + added)
        @text = nil
        @content_size = compute_content_size
        update_top_line_if_auto_scroll
        invalidate
      end

      # Verbatim append, returning `self` for chainability (`view << a << b`).
      # @param str [String, StyledString, nil]
      # @return [self]
      def <<(str)
        append(str)
        self
      end

      # Appends `str` as a new entry: starts a fresh hard line first (when
      # the buffer is non-empty) and then appends `str`. Equivalent to
      # `append("\n" + str)` on a non-empty buffer, or `append(str)` on an
      # empty one. `nil` and `""` produce a blank entry on a non-empty
      # buffer and a no-op on an empty buffer (matches the old `append`
      # semantics for "log line" callers).
      # @param str [String, StyledString, nil]
      # @return [void]
      def add_line(str)
        parsed = StyledString.parse(str)
        if empty? || @regions.last.empty?
          # No previous line in the tail region to break away from — just
          # append. (If the tail region is empty but earlier regions have
          # content, the verbatim {#append} path already starts a fresh
          # hard line in the tail.)
          append(parsed)
        else
          append(StyledString.plain("\n") + parsed)
        end
      end

      # Drops the last `n` hard lines from the buffer. The inverse of
      # building up a tail region with {#append} / {#add_line}: a caller
      # streaming partially-rendered content whose tail must occasionally
      # be retracted (e.g. Markdown-to-ANSI where a new token reformats
      # the table being built) can call `remove_last_n_lines(k)` followed
      # by `append(new_tail)` to replace the damaged region in place.
      #
      # `n == 0` and the empty-buffer case are no-ops (no invalidation).
      # `n >= hard-line count` empties the buffer.
      #
      # Operates on **hard lines** (the `\n`-delimited entries the
      # buffer stores), not on wrapped physical rows — same granularity
      # as {#add_line}. Cost is O(rendered-rows of the popped lines).
      # @param n [Integer] number of hard lines to drop; must be >= 0.
      # @raise [TypeError] if `n` isn't an `Integer`.
      # @raise [ArgumentError] if `n` is negative.
      # @return [void]
      def remove_last_n_lines(n)
        raise TypeError, "expected Integer, got #{n.inspect}" unless n.is_a?(Integer)
        raise ArgumentError, "n must not be negative, got #{n}" if n.negative?

        screen.check_locked
        return if n.zero? || empty?

        to_drop = [n, @hard_lines.size].min
        to_drop.times { pop_hard_line }

        # Cascade-shrink regions from the spatial tail. The tail region
        # gives up lines first; if more are still owed (because the tail
        # was shorter than `to_drop`), earlier regions shrink in turn.
        remaining = to_drop
        @regions.reverse_each do |region|
          break if remaining.zero?

          take = [remaining, region.line_count].min
          region.send(:line_count=, region.line_count - take)
          remaining -= take
        end

        @text = nil
        @content_size = compute_content_size
        @top_line = top_line_max if @top_line > top_line_max
        update_top_line_if_auto_scroll
        invalidate
      end

      # Replaces a contiguous range of hard lines with the parsed content
      # of `str`. The replacement is parsed exactly like {#text=} and
      # {#append}: a {String} is run through {StyledString.parse} (so
      # embedded ANSI is honored), a {StyledString} is used as-is, `nil`
      # behaves like an empty replacement (the range is deleted). Embedded
      # `"\n"` in the replacement produces multiple hard lines, so a single
      # `replace` can grow or shrink the buffer.
      #
      # `range` selects which hard lines to swap out:
      #
      # - an `Integer` `n` is shorthand for `n..n` (replace one existing
      #   line — `n` must be in `[0, hard-line count)`);
      # - a non-empty `Range` of hard-line indices replaces those lines;
      # - an empty `Range` (e.g. `2...2`, or the canonical end-insertion
      #   `hard_lines.size...hard_lines.size`) is *insertion* at that
      #   position — no lines are removed. {#insert} is a thin alias for
      #   this case.
      #
      # Endpoints must be non-negative integers; `begin` may equal
      # `hard-line count` (insertion at the end), `end` may not exceed
      # `hard-line count - 1`. `nil` endpoints (beginless / endless ranges)
      # are not accepted.
      #
      # Cost is roughly `O(from + length + new content)`: the splice
      # updates only the affected slice of the physical-row buffer, using
      # the per-hard-line wrap-count cache to locate the starting offset
      # without re-wrapping preceding lines. Lines outside the splice are
      # never re-wrapped. {#top_line} is clamped if the new line count
      # puts it past the end; {#auto_scroll} pins it to the bottom as
      # usual. The call is a no-op (no invalidation) when the parsed
      # replacement equals the covered range (vacuously true for an empty
      # range plus empty replacement, so `replace(n...n, "")` is a cheap
      # no-op).
      #
      # @param range [Range, Integer] hard-line indices to replace.
      # @param str [String, StyledString, nil] replacement content.
      # @raise [TypeError] if `range` is neither an `Integer` nor a `Range`,
      #   or if a `Range` endpoint is not an `Integer`, or if `str` is not
      #   a `String`, `StyledString`, or `nil`.
      # @raise [ArgumentError] if `range` has a negative endpoint, extends
      #   past the last hard line, or is malformed (`end` more than one
      #   below `begin`).
      # @return [void]
      def replace(range, str)
        screen.check_locked
        from, to = normalize_replace_range(range)

        parsed = StyledString.parse(str)
        new_hard_lines = parsed.empty? ? [] : parsed.lines
        length = to - from + 1
        return if new_hard_lines == @hard_lines[from, length]

        splice_hard_lines(from, length, new_hard_lines)
        update_region_counts(from, length, new_hard_lines.size)
        @text = nil
        @content_size = compute_content_size
        @top_line = top_line_max if @top_line > top_line_max
        update_top_line_if_auto_scroll
        invalidate
      end

      # Inserts `str` at hard-line index `at`. Equivalent to
      # `replace(at...at, str)` — a no-removal splice that grows the buffer
      # by the parsed line count. `at == hard-line count` is allowed and
      # appends at the end; for that case {#append} / {#add_line} are
      # usually more idiomatic.
      # @param at [Integer] 0-based hard-line index in `[0, hard-line count]`.
      # @param str [String, StyledString, nil] content to insert.
      # @return [void]
      def insert(at, str)
        replace(at...at, str)
      end

      # Clears the text. Equivalent to `text = ""`.
      # @return [void]
      def clear
        self.text = StyledString::EMPTY
      end

      # @param new_top_line [Integer] 0 or greater. Not clamped against the
      #   number of lines (matches {List#top_line=}).
      # @return [void]
      def top_line=(new_top_line)
        raise TypeError, "expected Integer, got #{new_top_line.inspect}" unless new_top_line.is_a? Integer
        raise ArgumentError, "top_line must not be negative, got #{new_top_line}" if new_top_line.negative?
        return if @top_line == new_top_line

        @top_line = new_top_line
        invalidate
      end

      # @param value [Symbol] `:gone` or `:visible`.
      # @return [void]
      def scrollbar_visibility=(value)
        raise ArgumentError, "expected :gone or :visible, got #{value.inspect}" unless %i[gone visible].include?(value)
        return if @scrollbar_visibility == value

        @scrollbar_visibility = value
        rewrap
        invalidate
      end

      # Sets `auto_scroll`. If true, immediately scrolls to the bottom.
      # @param value [Boolean]
      # @return [void]
      def auto_scroll=(value)
        @auto_scroll = value ? true : false
        update_top_line_if_auto_scroll
      end

      def focusable? = true

      def tab_stop? = true

      # @return [Size] longest hard-line's display width × number of hard
      #   lines. Reported on the *unwrapped* text — wrap-aware sizing would
      #   be circular (width depends on width). Empty text returns
      #   `Size.new(0, 0)`. Maintained incrementally by {#text=} and
      #   {#append}, so reads are O(1).
      attr_reader :content_size

      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless active?
        return true if super

        case key
        when *Keys::DOWN_ARROWS then move_top_line_by(1)
        when *Keys::UP_ARROWS   then move_top_line_by(-1)
        when Keys::PAGE_DOWN    then move_top_line_by(viewport_lines)
        when Keys::PAGE_UP      then move_top_line_by(-viewport_lines)
        when Keys::CTRL_D       then move_top_line_by(viewport_lines / 2)
        when Keys::CTRL_U       then move_top_line_by(-viewport_lines / 2)
        when *Keys::HOMES, "g"  then move_top_line_to(0)
        when *Keys::ENDS_, "G"  then move_top_line_to(top_line_max)
        else return false
        end
        true
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        case event.button
        when :scroll_down then move_top_line_by(4)
        when :scroll_up   then move_top_line_by(-4)
        end
      end

      # Paints the text into {#rect}.
      #
      # Skips the {Component#repaint} default's auto-clear: every row is
      # painted explicitly (with padded blanks past the last line), so the
      # "fully draw over your rect" contract is met without an upfront wipe.
      # @return [void]
      def repaint
        return if rect.empty?

        scrollbar = if scrollbar_visible?
                      VerticalScrollBar.new(rect.height, line_count: @physical_lines.size, top_line: @top_line)
                    end
        (0...rect.height).each do |row|
          line = paintable_line(row + @top_line, row, scrollbar)
          screen.print TTY::Cursor.move_to(rect.left, rect.top + row), line
        end
      end

      protected

      # Rewraps the text on width changes. Wrap width depends on
      # {#rect}`.width` and the scrollbar gutter, both of which trigger
      # this hook.
      # @return [void]
      def on_width_changed
        super
        rewrap
      end

      private

      # Validates and unpacks a {#replace}-style range argument into
      # inclusive `[from, to]` line indices. An `Integer` `n` becomes
      # `[n, n]` (which must point at an existing line — `Integer` is
      # never insertion sugar). A `Range` is normalized for
      # `exclude_end?`; `to == from - 1` is a valid empty range
      # (insertion at `from`), and `from` may equal `size` for
      # end-insertion. Shared by {#replace} and {Region#replace};
      # `size` is the buffer or region line count, and `what` is the
      # entity name woven into error messages.
      # @param range [Range, Integer]
      # @param size [Integer]
      # @param what [String]
      # @return [Array(Integer, Integer)]
      def normalize_replace_range(range, size = @hard_lines.size, what = "the buffer")
        case range
        when Integer
          from = to = range
        when Range
          from = range.begin
          raw_end = range.end
          unless from.is_a?(Integer) && raw_end.is_a?(Integer)
            raise TypeError, "range endpoints must be Integers, got #{range.inspect}"
          end

          to = range.exclude_end? ? raw_end - 1 : raw_end
        else
          raise TypeError, "expected Range or Integer, got #{range.inspect}"
        end
        raise ArgumentError, "range endpoints must not be negative, got #{range.inspect}" if from.negative?
        if from > size || to >= size
          raise ArgumentError, "range #{range.inspect} out of bounds for #{what} (#{size} hard line(s))"
        end
        raise ArgumentError, "range #{range.inspect} is malformed (end more than one below begin)" if to < from - 1

        [from, to]
      end

      # Hard-line index where `region` begins in {@hard_lines} — derived
      # by summing the line counts of all regions that precede it.
      # @param region [Region]
      # @return [Integer]
      def region_start_index(region)
        idx = @regions.index(region)
        raise "region not found in view" unless idx

        sum = 0
        idx.times { |i| sum += @regions[i].line_count }
        sum
      end

      # Joined {StyledString} of the hard lines that `region` owns. Mirrors
      # {#text} but scoped to one region.
      # @param region [Region]
      # @return [StyledString]
      def text_for_region(region)
        start = region_start_index(region)
        count = region.line_count
        return StyledString::EMPTY if count.zero?
        return @hard_lines[start] if count == 1

        newline = StyledString::Span.new(text: "\n", style: StyledString::Style::DEFAULT)
        spans = []
        count.times do |i|
          spans << newline if i.positive?
          spans.concat(@hard_lines[start + i].spans)
        end
        StyledString.new(spans)
      end

      # Replaces all of `region`'s hard lines with the parsed content of
      # `value`. Symmetric with {#text=}, scoped to one region. Empty/nil
      # content empties the region (no visible blank line). Works on
      # already-empty regions (insertion at the region's position).
      # @param region [Region]
      # @param value [String, StyledString, nil]
      # @return [void]
      def set_region_text(region, value)
        screen.check_locked
        parsed = StyledString.parse(value)
        new_lines = parsed.empty? ? [] : parsed.lines
        start = region_start_index(region)
        old_count = region.line_count
        return if new_lines == @hard_lines[start, old_count]

        splice_hard_lines(start, old_count, new_lines)
        region.send(:line_count=, new_lines.size)
        @text = nil
        @content_size = compute_content_size
        @top_line = top_line_max if @top_line > top_line_max
        update_top_line_if_auto_scroll
        invalidate
      end

      # Region-scoped {#replace}. Validates `range` against
      # `region.line_count`, translates region-relative indices to
      # absolute buffer indices, splices, and updates the region's count.
      # @param region [Region]
      # @param range [Range, Integer]
      # @param str [String, StyledString, nil]
      # @return [void]
      def replace_in_region(region, range, str)
        screen.check_locked
        from, to = normalize_replace_range(range, region.line_count, "the region")
        parsed = StyledString.parse(str)
        new_hard_lines = parsed.empty? ? [] : parsed.lines
        start = region_start_index(region)
        abs_from = start + from
        length = to - from + 1
        return if new_hard_lines == @hard_lines[abs_from, length]

        splice_hard_lines(abs_from, length, new_hard_lines)
        region.send(:line_count=, region.line_count - length + new_hard_lines.size)
        @text = nil
        @content_size = compute_content_size
        @top_line = top_line_max if @top_line > top_line_max
        update_top_line_if_auto_scroll
        invalidate
      end

      # Verbatim append into `region`.
      # @param region [Region]
      # @param str [String, StyledString, nil]
      # @return [void]
      def append_to_region(region, str)
        screen.check_locked
        parsed = StyledString.parse(str)
        return if parsed.empty?

        if region.equal?(@regions.last)
          append(parsed)
          return
        end

        new_segments = parsed.lines
        start = region_start_index(region)
        if region.empty?
          splice_hard_lines(start, 0, new_segments)
          region.send(:line_count=, new_segments.size)
        else
          last_idx = start + region.line_count - 1
          extension = new_segments.first
          rest = new_segments[1..]
          if extension.empty?
            return if rest.empty?

            splice_hard_lines(last_idx + 1, 0, rest)
          else
            extended = @hard_lines[last_idx] + extension
            splice_hard_lines(last_idx, 1, [extended, *rest])
          end
          region.send(:line_count=, region.line_count + rest.size)
        end
        @text = nil
        @content_size = compute_content_size
        @top_line = top_line_max if @top_line > top_line_max
        update_top_line_if_auto_scroll
        invalidate
      end

      # Drops the last `n` hard lines from `region`'s tail via
      # {#splice_hard_lines}. `n` is clamped to the region's current
      # line count; callers guarantee `n > 0` and the region is
      # non-empty (the {Region#remove_last_n_lines} guard handles the
      # no-op cases).
      # @param region [Region]
      # @param n [Integer]
      # @return [void]
      def remove_last_n_from_region(region, n)
        screen.check_locked
        to_drop = [n, region.line_count].min
        start = region_start_index(region)
        drop_from = start + region.line_count - to_drop
        splice_hard_lines(drop_from, to_drop, [])
        region.send(:line_count=, region.line_count - to_drop)
        @text = nil
        @content_size = compute_content_size
        @top_line = top_line_max if @top_line > top_line_max
        update_top_line_if_auto_scroll
        invalidate
      end

      # Drops `region` from {@regions}: its hard lines are removed via
      # {#splice_hard_lines}, the handle is detached, and the always-one
      # default is restored if the removal would have left zero regions.
      # Skips the rewrap / invalidate work when the region was empty
      # (the buffer didn't change), but always detaches.
      # @param region [Region]
      # @return [void]
      def remove_region(region)
        screen.check_locked
        had_lines = region.line_count.positive?
        if had_lines
          start = region_start_index(region)
          splice_hard_lines(start, region.line_count, [])
        end
        @regions.delete(region)
        region.send(:detach!)
        @regions << Region.send(:new, self) if @regions.empty?
        return unless had_lines

        @text = nil
        @content_size = compute_content_size
        @top_line = top_line_max if @top_line > top_line_max
        update_top_line_if_auto_scroll
        invalidate
      end

      # Adjusts region line counts after a {@hard_lines} splice that
      # removed `removed_count` lines at index `from` and inserted
      # `added_count` in their place. Two passes:
      #
      # 1. Subtract each region's overlap with the removed range (uses
      #    the original counts to compute positions). Remember the first
      #    region that lost lines — that's the natural home for the
      #    replacement content.
      # 2. Credit `added_count` to that region. For pure insertions (no
      #    removal), there's no "first overlapping region" to pick from;
      #    walk regions and credit the latest one starting at `from` (the
      #    boundary tiebreaker matches the spatial-tail-routing of
      #    {#append}). Past-the-end inserts fall back to the tail region.
      # @param from [Integer]
      # @param removed_count [Integer]
      # @param added_count [Integer]
      # @return [void]
      def update_region_counts(from, removed_count, added_count)
        target = nil
        pos = 0
        @regions.each do |region|
          original_count = region.line_count
          overlap_start = [from, pos].max
          overlap_end = [from + removed_count, pos + original_count].min
          overlap = overlap_end - overlap_start
          if overlap.positive?
            region.send(:line_count=, original_count - overlap)
            target ||= region
          end
          pos += original_count
        end
        return if added_count.zero?

        if target.nil?
          pos = 0
          @regions.each do |region|
            region_end_exclusive = pos + region.line_count
            if from == pos
              target = region
            elsif from < region_end_exclusive
              target = region
              break
            end
            pos = region_end_exclusive
          end
          target ||= @regions.last
        end
        target.send(:line_count=, target.line_count + added_count)
      end

      # @return [Integer] number of visible lines.
      def viewport_lines = rect.height

      # @return [Integer] the max value of {#top_line} for scroll-key clamping.
      def top_line_max = (@physical_lines.size - viewport_lines).clamp(0, nil)

      # Full rebuild of {@physical_lines} and {@hard_line_wrap_counts}
      # from {@hard_lines}. Called when wrap width changes (which
      # invalidates every cached row count) and from {#text=} (which
      # replaces the whole logical model). Mid-buffer mutators splice
      # incrementally via {#splice_hard_lines} and do *not* go through
      # here. Clamps {@top_line} if the new line count puts it out of
      # range.
      # @return [void]
      def rewrap
        width = wrap_width
        @blank_line = pad_to(StyledString::EMPTY, width)
        @physical_lines = []
        @hard_line_wrap_counts = []
        @hard_lines.each do |hl|
          rows, n = wrap_hard_line(hl, width)
          @physical_lines.concat(rows)
          @hard_line_wrap_counts << n
        end
        @top_line = top_line_max if @top_line > top_line_max
      end

      # Wraps `hard_line` at `width` and returns the padded physical rows
      # alongside the row count. Empty hard lines (e.g. from a `"\n\n"`
      # run) and degenerate `width <= 0` both emit a single {@blank_line}
      # row, matching what `@text.wrap(width).map { |l| pad_to(l, width) }`
      # would have produced.
      # @param hard_line [StyledString]
      # @param width [Integer]
      # @return [Array(Array<StyledString>, Integer)]
      def wrap_hard_line(hard_line, width)
        return [[@blank_line], 1] if hard_line.empty? || width <= 0

        wrapped = hard_line.wrap(width)
        [wrapped.map { |line| pad_to(line, width) }, wrapped.size]
      end

      # Appends `hard_line` to the tail of {@hard_lines}, updating the
      # wrap-count cache and {@physical_lines} in lockstep.
      # @param hard_line [StyledString]
      # @param width [Integer]
      # @return [void]
      def push_hard_line(hard_line, width)
        rows, n = wrap_hard_line(hard_line, width)
        @hard_lines << hard_line
        @hard_line_wrap_counts << n
        @physical_lines.concat(rows)
      end

      # Pops the last hard line, the corresponding cache entry, and the
      # physical rows that hard line contributed. Returns the popped
      # hard line.
      # @return [StyledString]
      def pop_hard_line
        n = @hard_line_wrap_counts.pop
        n.times { @physical_lines.pop }
        @hard_lines.pop
      end

      # Splices `new_hard_lines` into the buffer in place of the `count`
      # hard lines starting at index `from`. Updates {@hard_lines},
      # {@hard_line_wrap_counts}, and {@physical_lines} consistently.
      # The starting physical-row offset is computed in O(`from`) integer
      # adds via the cache — no wraps of preceding hard lines. Wraps are
      # done only for the new content, so total cost is
      # `O(from + count + new_hard_lines.sum(&:display_width))`.
      # @param from [Integer]
      # @param count [Integer] number of existing hard lines to remove.
      # @param new_hard_lines [Array<StyledString>]
      # @return [void]
      def splice_hard_lines(from, count, new_hard_lines)
        width = wrap_width
        phys_start = phys_offset_at(from)
        old_phys_count = @hard_line_wrap_counts[from, count].sum

        @hard_lines[from, count] = new_hard_lines

        new_rows = []
        new_counts = []
        new_hard_lines.each do |hl|
          rows, n = wrap_hard_line(hl, width)
          new_rows.concat(rows)
          new_counts << n
        end

        @hard_line_wrap_counts[from, count] = new_counts
        @physical_lines[phys_start, old_phys_count] = new_rows
      end

      # @param idx [Integer]
      # @return [Integer] the {@physical_lines} index where the hard line
      #   at {@hard_lines}`[idx]` starts. O(`idx`) integer adds via the
      #   wrap-count cache.
      def phys_offset_at(idx)
        return 0 if idx.zero?

        @hard_line_wrap_counts[0, idx].sum
      end

      # Rebuilds the joined {StyledString} from {@hard_lines}, inserting a
      # default-styled `"\n"` between hard lines. Called from the {#text}
      # reader when the cache is cold. Cost is O(total spans).
      # @return [StyledString]
      def build_text
        return StyledString::EMPTY if @hard_lines.empty?
        return @hard_lines.first if @hard_lines.size == 1

        newline = StyledString::Span.new(text: "\n", style: StyledString::Style::DEFAULT)
        spans = []
        @hard_lines.each_with_index do |hl, i|
          spans << newline if i.positive?
          spans.concat(hl.spans)
        end
        StyledString.new(spans)
      end

      # @return [Size] {#content_size} computed from {@hard_lines}.
      def compute_content_size
        return Size::ZERO if @hard_lines.empty?

        Size.new(@hard_lines.map(&:display_width).max || 0, @hard_lines.size)
      end

      # @return [Integer] column width available for wrapped text — viewport
      #   width minus the scrollbar gutter (when visible). `0` when {#rect}'s
      #   width is non-positive, which yields a degenerate "no wrap" result.
      def wrap_width
        return 0 if rect.width <= 0

        rect.width - (scrollbar_visible? ? 1 : 0)
      end

      # @param delta [Integer] negative scrolls up, positive scrolls down.
      # @return [void]
      def move_top_line_by(delta)
        move_top_line_to(@top_line + delta)
      end

      # @param target [Integer] desired top line; clamped to `[0, top_line_max]`.
      # @return [void]
      def move_top_line_to(target)
        clamped = target.clamp(0, top_line_max)
        self.top_line = clamped unless @top_line == clamped
      end

      # @return [void]
      def update_top_line_if_auto_scroll
        return unless @auto_scroll

        target = (@physical_lines.size - viewport_lines).clamp(0, nil)
        self.top_line = target if @top_line != target
      end

      # @return [Boolean]
      def scrollbar_visible?
        return false if rect.empty?

        @scrollbar_visibility == :visible
      end

      # Pads `line` with trailing default-styled spaces out to `width` display
      # columns. Callers rely on {StyledString#wrap} having already
      # constrained the line to `<= width`, so no truncation is performed.
      # `width <= 0` returns {StyledString::EMPTY} to handle the degenerate
      # `wrap_width == 0` case (rect.width == 1 with scrollbar).
      # @param line [StyledString]
      # @param width [Integer]
      # @return [StyledString]
      def pad_to(line, width)
        return StyledString::EMPTY if width <= 0

        diff = width - line.display_width
        return line if diff <= 0

        line + StyledString.plain(" " * diff)
      end

      # @param index [Integer] 0-based index into `@physical_lines`.
      # @param row_in_viewport [Integer] 0-based row within the viewport.
      # @param scrollbar [VerticalScrollBar, nil]
      # @return [String] paintable ANSI-encoded line exactly `rect.width`
      #   columns wide. Body lines come pre-padded from {#rewrap}, so this
      #   reduces to a memoized {StyledString#to_ansi} read plus an
      #   ASCII-string concat of the scrollbar glyph when one is present.
      def paintable_line(index, row_in_viewport, scrollbar)
        line = @physical_lines[index] || @blank_line
        return line.to_ansi unless scrollbar

        line.to_ansi + scrollbar.scrollbar_char(row_in_viewport)
      end

      # A logical section of a {TextView}'s text — a contiguous run of
      # hard lines the app wants to address as a unit (e.g. an LLM's
      # "thinking" output vs. its assistant message). The view always
      # has at least one region, an internal default that owns whatever
      # hard lines aren't claimed by an app-created region.
      #
      # Apps don't construct regions directly; call {TextView#create_region}
      # to get one. The handle stays valid as long as the region is
      # attached — i.e. until {TextView#text=} (or {TextView#clear}) wipes
      # the slate and installs a fresh internal default. Detached regions
      # raise {RuntimeError} on every mutator and reader.
      #
      # A region's position is derived from its sibling order and counts,
      # so growing or shrinking an earlier region implicitly shifts the
      # ranges of all later regions. Empty regions occupy zero rows but
      # still hold a position in the sequence; `region.text = ""` collapses
      # a region's visible footprint without detaching it. Pre-creating
      # empty placeholder regions is supported and is the natural pattern
      # for "I'll fill this in later" layouts.
      class Region
        # @param view [TextView] the owning view (never `nil` at construction).
        # @param line_count [Integer] number of hard lines this region owns.
        def initialize(view, line_count = 0)
          @view = view
          @line_count = line_count
        end

        private_class_method :new

        # @return [Integer] number of hard lines this region owns. Safe to
        #   read on a detached region (no error raised).
        attr_reader :line_count

        # @return [Boolean] `true` while the region is owned by its
        #   {TextView}. Becomes `false` permanently once detached
        #   (typically by {TextView#text=} / {TextView#clear}).
        def attached?
          !@view.nil?
        end

        # @return [Boolean] true iff the region owns zero hard lines.
        #   Empty regions render nothing — they still hold a position in
        #   the sequence, so subsequent mutations route to them as usual.
        def empty? = @line_count.zero?

        # @return [StyledString] the joined content of just this region's
        #   hard lines. Empty regions return {StyledString::EMPTY}.
        # @raise [RuntimeError] when the region is detached.
        def text
          check_attached
          @view.send(:text_for_region, self)
        end

        # Replaces all of this region's hard lines with the parsed content
        # of `value`. Accepts the same inputs as {TextView#text=}; empty
        # or `nil` content collapses the region to zero hard lines.
        # @param value [String, StyledString, nil]
        # @raise [RuntimeError] when the region is detached.
        # @return [void]
        def text=(value)
          check_attached
          @view.send(:set_region_text, self, value)
        end

        # Verbatim append into this region's tail. Same semantics as
        # {TextView#append} but scoped to the region: embedded `"\n"`
        # creates new hard lines within the region, no-leading-newline
        # input extends the region's last hard line. Empty / `nil` input
        # is a no-op (but still raises when detached). When the region is
        # the spatial tail of the view, this uses the incremental
        # {TextView#append} path; mid-document regions splice the affected
        # slice of the physical-row buffer (lines outside the region are
        # not re-wrapped).
        # @param str [String, StyledString, nil]
        # @raise [RuntimeError] when the region is detached.
        # @return [void]
        def append(str)
          check_attached
          @view.send(:append_to_region, self, str)
        end
        alias << append

        # @return [Range] the hard-line indices this region currently
        #   occupies — `start...(start + line_count)`. Empty regions
        #   return a degenerate exclusive range at their position (e.g.
        #   `5...5`). The result is computed on each call and so always
        #   reflects sibling mutations.
        # @raise [RuntimeError] when the region is detached.
        def range
          check_attached
          start = @view.send(:region_start_index, self)
          start...(start + @line_count)
        end

        # Removes this region from its view. The region's hard lines (if
        # any) are deleted from the buffer — subsequent regions' ranges
        # shift up by `line_count` — and the handle detaches permanently.
        # The view keeps its always-≥1-region invariant: if this was the
        # only remaining region, a fresh internal default is installed
        # (the app doesn't get a handle to it; call
        # {TextView#create_region} again to start tracking).
        #
        # Idempotent: calling `remove` on an already-detached region is a
        # silent no-op (unlike the other mutators, which raise). This
        # lets cleanup paths blindly call `remove` without first checking
        # {#attached?}.
        # @return [void]
        def remove
          return unless attached?

          @view.send(:remove_region, self)
        end

        # Appends `str` as a new entry in this region: starts a fresh
        # hard line first (when the region is non-empty), then appends
        # `str`. Scoped equivalent of {TextView#add_line}. On an empty
        # region behaves like {#append}.
        # @param str [String, StyledString, nil]
        # @raise [RuntimeError] when the region is detached.
        # @return [void]
        def add_line(str)
          check_attached
          parsed = StyledString.parse(str)
          if empty?
            append(parsed)
          else
            append(StyledString.plain("\n") + parsed)
          end
        end

        # Replaces a contiguous range of this region's hard lines with the
        # parsed content of `str`. Region-scoped counterpart of
        # {TextView#replace}: indices are 0-based **within the region**
        # (so `replace(0, "x")` rewrites the region's first line, not
        # the buffer's). Same range conventions apply — `Integer`,
        # inclusive/exclusive `Range`, empty range as insertion at
        # `begin`, and `begin == line_count` for end-insertion.
        # @param range [Range, Integer] region-relative hard-line indices.
        # @param str [String, StyledString, nil] replacement content.
        # @raise [RuntimeError] when the region is detached.
        # @raise [TypeError] when `range` or `str` has the wrong type.
        # @raise [ArgumentError] on negative, malformed, or out-of-bounds
        #   ranges.
        # @return [void]
        def replace(range, str)
          check_attached
          @view.send(:replace_in_region, self, range, str)
        end

        # Inserts `str` at region-relative hard-line index `at`.
        # Equivalent to `replace(at...at, str)`. Region-scoped counterpart
        # of {TextView#insert}; `at == line_count` is allowed and appends
        # at the region's tail.
        # @param at [Integer] region-relative index in `[0, line_count]`.
        # @param str [String, StyledString, nil]
        # @raise [RuntimeError] when the region is detached.
        # @return [void]
        def insert(at, str)
          replace(at...at, str)
        end

        # Drops the last `n` hard lines from this region's tail.
        # Subsequent regions' ranges shift up by the number actually
        # dropped. `n` is clamped to {#line_count}, so passing a large
        # `n` empties the region — the handle stays attached (use
        # {#remove} when the goal is to drop the region itself).
        # `n == 0` and an already-empty region are no-ops.
        # @param n [Integer]
        # @raise [RuntimeError] when the region is detached.
        # @raise [TypeError] when `n` is not an `Integer`.
        # @raise [ArgumentError] when `n` is negative.
        # @return [void]
        def remove_last_n_lines(n)
          check_attached
          raise TypeError, "expected Integer, got #{n.inspect}" unless n.is_a?(Integer)
          raise ArgumentError, "n must not be negative, got #{n}" if n.negative?
          return if n.zero? || empty?

          @view.send(:remove_last_n_from_region, self, n)
        end

        private

        attr_writer :line_count

        # @return [void]
        def detach!
          @view = nil
        end

        # @return [void]
        def check_attached
          raise "region is detached" unless attached?
        end
      end
    end
  end
end
