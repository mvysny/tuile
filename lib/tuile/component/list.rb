# frozen_string_literal: true

module Tuile
  class Component
    # A scrollable list of typed items, one row each, with cursor support.
    #
    #   list = Component::List.new
    #   list.items    = people
    #   list.renderer = ->(p) { StyledString.plain(p.name) + screen.theme.hint(" #{p.email}") }
    #   list.cursor   = List::Cursor.new                  # a bare list has none
    #   list.on_item_chosen = ->(index, person) { open(person) }
    #
    # The {#renderer} turns an item into one row; the default renders an item
    # as itself, so a list of `String`s or {StyledString}s needs none — which
    # is what {#lines=} and {#build_lines} are, items that are their own
    # rendering (split on `\n`, one row per line).
    #
    # There are no appenders. The items are always assigned whole — an app that
    # grows a list keeps its own array and re-assigns it (`list.items = mine`) —
    # so a `List` stays a *snapshot of a collection*, which is the only shape a
    # lazily-sourced provider could ever fill.
    #
    # Rows wider than the viewport are ellipsized via {StyledString#ellipsize}
    # with span styles preserved across the cut. Vertical scrolling is via
    # {#top_line}; enable {#auto_scroll} to keep the bottom in view. The cursor
    # responds to arrows, `jk`, Home/End, Ctrl+U/D and scrolls the list
    # automatically; its highlight overlays {Theme#active_bg_color} while
    # preserving each span's foreground color.
    #
    # == Implementation details
    # Rendering is lazy: only the rows in the viewport are rendered, each
    # memoized until {#items=}, {#renderer=} or a width change drops the cache.
    # So a renderer runs *at paint time*, on any frame — keep it pure and
    # cheap; work that reaches a service belongs in the item, not in the
    # renderer. {#select_next} deliberately renders without memoizing: one
    # failed scan would otherwise cache a row per item.
    class List < Component
      # The default {#renderer}: an item renders as itself. Every renderer's
      # output is coerced the same way — a {StyledString} passes through, a
      # `String` is parsed (so embedded ANSI is honored), anything else is
      # `#to_s`'d first.
      # @return [Proc]
      DEFAULT_RENDERER = :itself.to_proc

      def initialize
        super
        @items = []
        @renderer = DEFAULT_RENDERER
        @row_cache = {}
        @blank_row = nil
        @auto_scroll = false
        @follow = true
        @top_line = 0
        @cursor = Cursor::None.new
        @scrollbar_visibility = :gone
        @show_cursor_when_inactive = false
        @on_item_chosen = nil
        @on_cursor_changed = nil
        @last_cursor_state = cursor_state
      end

      # @return [Proc, nil] callback fired when an item is chosen — by pressing
      #   Enter on the cursor's item, or by left-clicking it. Called as
      #   `proc.call(index, item)` with the chosen 0-based index and the item
      #   itself. Never fires when the cursor's position is outside the content
      #   (e.g. {Cursor::None}, or empty content).
      attr_accessor :on_item_chosen

      # @return [Proc, nil] callback fired when the `(index, item)` tuple under
      #   the cursor changes (items compared with `==`). Called as
      #   `proc.call(index, item)`, with `item` `nil` when the cursor is
      #   off-content ({Cursor::None}, empty list, or `index` past the last
      #   item). Fires on cursor moves (key, mouse, search), on {#cursor=},
      #   and on {#items=} when the item at the cursor's index
      #   changes (or its in-range/out-of-range status flips). Useful for
      #   keeping a details pane in sync with the highlighted row.
      attr_accessor :on_cursor_changed

      # @return [Boolean] if true and new content is set, auto-scrolls to the
      #   bottom — but only while the viewport is already pinned to the last
      #   line (see {#following?}). Scroll up to read older content and
      #   incoming rows stop yanking you back down; scroll back to the bottom
      #   and tailing resumes.
      attr_reader :auto_scroll

      # @return [Boolean] whether {#auto_scroll} is currently tailing. True
      #   while the viewport sits at the last line; flips to false the moment
      #   the user scrolls up, and back to true once they scroll to the bottom
      #   again. Only consulted when {#auto_scroll} is enabled.
      def following? = @follow

      # @return [Integer] top line of the viewport. 0 or positive.
      attr_reader :top_line

      # @return [Cursor] the list's cursor.
      attr_reader :cursor

      # @return [Symbol] scrollbar visibility: `:gone` or `:visible`.
      attr_reader :scrollbar_visibility

      # @return [Boolean] when true, the cursor highlight is painted even while
      #   the list is inactive (e.g. when focus is on a sibling search field).
      #   Defaults to false.
      attr_reader :show_cursor_when_inactive

      # @param value [Boolean]
      def show_cursor_when_inactive=(value)
        value = value ? true : false
        return if @show_cursor_when_inactive == value

        @show_cursor_when_inactive = value
        invalidate
      end

      # Sets the scrollbar visibility.
      # @param value [Symbol] `:gone` or `:visible`.
      def scrollbar_visibility=(value)
        raise ArgumentError, "expected :gone or :visible, got #{value.inspect}" unless %i[gone visible].include?(value)
        return if @scrollbar_visibility == value

        @scrollbar_visibility = value
        drop_row_cache
        invalidate
      end

      # Sets the new auto_scroll. If true, re-engages tailing and immediately
      # scrolls to the bottom.
      # @param new_auto_scroll [Boolean]
      def auto_scroll=(new_auto_scroll)
        @auto_scroll = new_auto_scroll
        @follow = true if new_auto_scroll
        update_top_line_if_auto_scroll
      end

      # Sets a new cursor.
      # @param cursor [Cursor] new cursor.
      def cursor=(cursor)
        raise TypeError, "expected Cursor, got #{cursor.inspect}" unless cursor.is_a? Cursor

        old_position = @cursor.position
        @cursor = cursor
        invalidate if old_position != cursor.position
        notify_cursor_changed
      end

      # Sets the top line.
      # @param new_top_line [Integer] 0 or greater.
      def top_line=(new_top_line)
        raise TypeError, "expected Integer, got #{new_top_line.inspect}" unless new_top_line.is_a? Integer
        raise ArgumentError, "top_line must not be negative, got #{new_top_line}" if new_top_line.negative?
        return unless @top_line != new_top_line

        @top_line = new_top_line
        @follow = at_bottom?
        invalidate
      end

      # @return [Array] the items, one row each.
      attr_reader :items

      # @return [Proc, Method] item -> row: a {StyledString}, a `String` (parsed,
      #   so embedded ANSI is honored), or anything with `#to_s`. Only the first
      #   line of a multi-line rendering is kept — one item is one row.
      attr_reader :renderer

      # Replaces the items, leaving the cursor where it is — a cursor left past
      # the last item strands off-content: no highlight, a dead Enter, and a
      # caller resolving `items[position]` gets `nil`. A caller that cares
      # clamps it (`cursor.go_to_last(items.size)`).
      # @param new_items [Array] one row each; rendered by {#renderer}.
      # @raise [TypeError] unless `new_items` is an `Array`.
      # @return [void]
      def items=(new_items)
        raise TypeError, "expected Array, got #{new_items.inspect}" unless new_items.is_a? Array

        @items = new_items
        drop_row_cache
        update_top_line_if_auto_scroll
        notify_cursor_changed
        invalidate
      end

      # @param proc [Proc, Method] item -> row; see {#renderer}.
      # @return [void]
      def renderer=(proc)
        @renderer = proc
        drop_row_cache
        invalidate
      end

      # Re-renders every row — for a {#renderer} whose *inputs* changed while
      # it and {#items} stayed the same, e.g. one prefixing a marker read from
      # a selection it closes over:
      #
      #   def value=(new_value)   # RadioGroup: the marked row moved
      #     super
      #     content.refresh_rows
      #   end
      #
      # @return [void]
      def refresh_rows
        drop_row_cache
        invalidate
      end

      # Sets the items from line-flavored input: each entry is coerced into a
      # {StyledString} (a `String` is parsed via {StyledString.parse}, so
      # embedded ANSI is honored; a {StyledString} is used as-is; anything else
      # is stringified via `#to_s` first), then split on `\n` into separate
      # lines via {StyledString#lines}, with trailing empty pieces dropped and
      # trailing ASCII whitespace stripped. The resulting {StyledString}s
      # *are* the {#items}, so under the
      # {DEFAULT_RENDERER} each is its own row.
      # @param lines [Array] entries are `String`, `StyledString`, or anything
      #   that responds to `#to_s`.
      # @return [void]
      def lines=(lines)
        raise TypeError, "expected Array, got #{lines.inspect}" unless lines.is_a? Array

        self.items = parse_input_lines(lines)
      end

      # Fully re-populates the list, line-flavored: yields a fresh buffer and
      # assigns it through {#lines=}, so each entry is coerced, split and
      # rstripped exactly as there. The buffer is a plain `Array`, which a
      # builder can read mid-build — recording the row a {Cursor::Limited} may
      # land on is the case this exists for:
      # ```ruby
      # list.build_lines do |lines|
      #   cursor_positions << lines.size
      #   lines << format_overview(vm)
      #   lines << format_detail(vm)
      # end
      # ```
      # @yield [buffer]
      # @yieldparam buffer [Array] mutable buffer to push lines into. Each
      #   entry is parsed the same way as the items passed to {#lines=}.
      # @yieldreturn [void]
      # @return [void]
      def build_lines
        buffer = []
        yield buffer
        self.lines = buffer
      end

      # @deprecated Use {#items}: the two return the same array, and this name
      #   lies once a {#renderer} is set — a list of typed items holds no
      #   lines. For the block form use {#build_lines}.
      # @raise [ArgumentError] if given a block — this used to be the builder,
      #   and silently ignoring it would leave the list unpopulated.
      # @return [Array] the items.
      def lines
        raise ArgumentError, "List#lines takes no block; use #build_lines" if block_given?

        @items
      end

      def focusable? = true

      def tab_stop? = true

      # @param key [String] a key.
      # @return [Boolean] true if the key was handled.
      def handle_key(key)
        if key == Keys::PAGE_UP
          move_top_line_by(-viewport_lines)
          true
        elsif key == Keys::PAGE_DOWN
          move_top_line_by(viewport_lines)
          true
        elsif key == Keys::ENTER && cursor_on_item?
          fire_item_chosen
          true
        elsif @cursor.handle_key(key, @items.size, viewport_lines)
          move_viewport_to_cursor
          notify_cursor_changed
          invalidate
          true
        else
          false
        end
      end

      # Moves the cursor to the next line whose text contains `query`
      # (case-insensitive substring match). Search wraps around the end of the
      # list. Only lines reachable by the current {#cursor} are considered.
      # Matching uses the line's plain text — span styles do not affect the
      # match.
      #
      # @param query [String] substring to match. Empty query never matches.
      # @param include_current [Boolean] when true, the current cursor position
      #   is eligible (useful when the query has just changed and the current
      #   line may still match); when false, the search starts after the
      #   current position (useful for "find next" key bindings that should
      #   advance past the current).
      # @return [Boolean] true if a match was found.
      def select_next(query, include_current: false)
        search_and_go(query, include_current: include_current, reverse: false)
      end

      # Mirror of {#select_next} that walks the list backwards.
      # @param query [String]
      # @param include_current [Boolean]
      # @return [Boolean] true if a match was found.
      def select_prev(query, include_current: false)
        search_and_go(query, include_current: include_current, reverse: true)
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        if event.button == :scroll_down
          move_top_line_by(4)
        elsif event.button == :scroll_up
          move_top_line_by(-4)
        else
          return unless rect.contains?(event.point)

          line = event.y - rect.top + top_line
          if @cursor.handle_mouse(line, event, @items.size)
            move_viewport_to_cursor
            notify_cursor_changed
            invalidate
          end
          fire_item_chosen if event.button == :left && line >= 0 && line < @items.size && cursor_on_item?
        end
      end

      # Paints the visible items into {#rect}, rendering the ones not already
      # cached.
      #
      # Skips the {Component#repaint} default's auto-clear: every row of
      # {#rect} is painted below (with blank padding past the last item),
      # so the parent contract — "fully draw over your rect" — is met
      # without an upfront wipe. Rows go through {Component#draw_line}, so
      # content *and* blank filler inherit {Component#effective_bg_color}
      # (a {#bg_color} set here or on an ancestor); the cursor row's
      # {Theme#active_bg_color} highlight composes on top of it.
      # @return [void]
      def repaint
        return if rect.empty?

        scrollbar = if scrollbar_visible?
                      VerticalScrollBar.new(rect.height, line_count: @items.size, top_line: @top_line)
                    end
        (0...rect.height).each do |row|
          draw_line(rect.left, row + rect.top, paintable_row(row + @top_line, row, scrollbar))
        end
      end

      # Tracks cursor position within the list.
      class Cursor
        # @param position [Integer] the initial cursor position.
        def initialize(position: 0)
          raise "invalid position #{position}" unless position.is_a? Integer

          @position = position
        end

        # No cursor — cursor is disabled.
        class None < Cursor
          def initialize
            super(position: -1)
            freeze
          end

          # @param _key [String]
          # @param _line_count [Integer]
          # @param _viewport_lines [Integer]
          # @return [Boolean]
          def handle_key(_key, _line_count, _viewport_lines)
            false
          end

          # @param _line [Integer]
          # @param _event [MouseEvent]
          # @param _line_count [Integer]
          # @return [Boolean]
          def handle_mouse(_line, _event, _line_count)
            false
          end

          # @param _line_count [Integer]
          # @return [Array<Integer>]
          def candidate_positions(_line_count)
            []
          end

          # Overridden so all movement funnels — base {Cursor#go_to_last},
          # {Cursor#go_to_first}, etc., which all call {#go} — become safe
          # no-ops on a disabled cursor. The instance is frozen, so a default
          # mutating {#go} would raise.
          # @param _new_position [Integer]
          # @return [Boolean] always false.
          def go(_new_position)
            false
          end
        end

        # @return [Integer] 0-based line index of the current cursor position.
        attr_reader :position

        # @param line_count [Integer] number of lines in the list.
        # @return [Array<Integer>] positions the cursor can land on, in
        #   ascending order.
        def candidate_positions(line_count)
          (0...line_count).to_a
        end

        # @param key [String] pressed keyboard key.
        # @param line_count [Integer] number of lines in the list.
        # @param viewport_lines [Integer] number of visible lines.
        # @return [Boolean] true if the cursor moved.
        def handle_key(key, line_count, viewport_lines)
          case key
          when *Keys::DOWN_ARROWS
            go_down_by(1, line_count)
          when *Keys::UP_ARROWS
            go_up_by(1)
          when *Keys::HOMES
            go_to_first
          when *Keys::ENDS_
            go_to_last(line_count)
          when Keys::CTRL_U
            go_up_by(viewport_lines / 2)
          when Keys::CTRL_D
            go_down_by(viewport_lines / 2, line_count)
          else
            false
          end
        end

        # @param line [Integer] cursor is hovering over this line.
        # @param event [MouseEvent] the event.
        # @param line_count [Integer] number of lines in the list.
        # @return [Boolean] true if the event was handled.
        def handle_mouse(line, event, line_count)
          if event.button == :left
            go(line.clamp(nil, line_count - 1))
          else
            false
          end
        end

        # Moves the cursor to the new position. Public only because of testing.
        # @param new_position [Integer] new 0-based cursor position.
        # @return [Boolean] true if the position changed.
        def go(new_position)
          new_position = new_position.clamp(0, nil)
          return false if @position == new_position

          @position = new_position
          true
        end

        # Moves the cursor to the last reachable position. For base {Cursor},
        # the last line; {Limited} clamps to the last allowed position; {None}
        # is a no-op.
        # @param line_count [Integer] number of lines in the list.
        # @return [Boolean] true if the position changed.
        def go_to_last(line_count)
          go(line_count - 1)
        end

        protected

        # @param lines [Integer]
        # @param line_count [Integer]
        # @return [Boolean]
        def go_down_by(lines, line_count)
          go((@position + lines).clamp(nil, line_count - 1))
        end

        # @param lines [Integer]
        # @return [Boolean]
        def go_up_by(lines)
          go(@position - lines)
        end

        # @return [Boolean]
        def go_to_first
          go(0)
        end

        # Cursor which can only land on specific allowed lines.
        class Limited < Cursor
          # @param positions [Array<Integer>] allowed positions. Must not be
          #   empty.
          # @param position [Integer] initial position.
          def initialize(positions, position: positions[0])
            raise "positions are empty" if positions.empty?

            @positions = positions.sort
            position = @positions[@positions.rindex { _1 < position } || 0] unless @positions.include?(position)
            super(position: position)
          end

          # @param line [Integer]
          # @param event [MouseEvent]
          # @param _line_count [Integer]
          # @return [Boolean]
          def handle_mouse(line, event, _line_count)
            if event.button == :left
              prev_pos = @positions.reverse_each.find { _1 <= line }
              return go_to_first if prev_pos.nil?

              go(prev_pos)
            else
              false
            end
          end

          # @param line_count [Integer]
          # @return [Array<Integer>]
          def candidate_positions(line_count)
            @positions.select { _1 < line_count }
          end

          # @param _line_count [Integer]
          # @return [Boolean]
          def go_to_last(_line_count)
            go(@positions.last)
          end

          protected

          # @param lines [Integer]
          # @param line_count [Integer]
          # @return [Boolean]
          def go_down_by(lines, line_count)
            next_pos = @positions.find { _1 >= @position + lines }
            return go_to_last(line_count) if next_pos.nil?

            go(next_pos)
          end

          # @param lines [Integer]
          # @return [Boolean]
          def go_up_by(lines)
            prev_pos = @positions.reverse_each.find { _1 <= @position - lines }
            return go_to_first if prev_pos.nil?

            go(prev_pos)
          end

          # @return [Boolean]
          def go_to_first
            go(@positions.first)
          end
        end
      end

      protected

      # Drops the rendered-row cache when the wrap width changes. The wrap
      # width depends on {#rect}`.width` and the scrollbar gutter, both of
      # which trigger this hook. Also re-evaluates {#auto_scroll}: if items were
      # assigned while the rect was empty (e.g. a {Popup}-wrapped list was
      # populated before the popup was opened), the auto-scroll update
      # was skipped because there was no viewport — re-run it now that there
      # is one, so the list snaps to the bottom on first paint.
      # @return [void]
      def on_width_changed
        super
        drop_row_cache
        update_top_line_if_auto_scroll
      end

      private

      # Coerces and flattens a list of input entries into trimmed
      # {StyledString} lines. Each entry becomes a {StyledString} (String
      # via {StyledString.parse}, StyledString passed through, anything else
      # via `#to_s`), then split on `\n` via {StyledString#lines} — with
      # trailing empty pieces dropped (matching `String#split("\n")`'s
      # default behavior, so a lone `""` entry adds no row) — and trailing ASCII
      # whitespace stripped on each resulting line.
      # @param entries [Array]
      # @return [Array<StyledString>]
      def parse_input_lines(entries)
        entries.flat_map { |entry| split_to_lines(entry) }
      end

      # @param entry [Object]
      # @return [Array<StyledString>]
      def split_to_lines(entry)
        styled = entry.is_a?(StyledString) ? entry : StyledString.parse(entry.to_s)
        parts = styled.lines
        parts.pop while parts.last && parts.last.empty?
        parts.map { |line| rstrip_styled(line) }
      end

      # Returns `line` with trailing ASCII whitespace (space/tab) dropped,
      # preserving span styles on the surviving prefix. Whitespace chars are
      # all single-column ASCII, so byte-count delta equals column-count
      # delta and {StyledString#slice} can do the cut.
      # @param line [StyledString]
      # @return [StyledString]
      def rstrip_styled(line)
        plain = line.to_s
        trailing = plain.length - plain.rstrip.length
        return line if trailing.zero?
        return StyledString::EMPTY if trailing == plain.length

        line.slice(0, line.display_width - trailing)
      end

      # @return [Boolean] true if the cursor sits on a real item.
      def cursor_on_item?
        pos = @cursor.position
        pos >= 0 && pos < @items.size
      end

      # Calls {#on_item_chosen} with the cursor's current `(index, item)`.
      # Caller must ensure {#cursor_on_item?}.
      # @return [void]
      def fire_item_chosen
        pos = @cursor.position
        @on_item_chosen&.call(pos, @items[pos])
      end

      # @return [Array((Integer, Object, nil))]
      #   `[position, item_at_position]`, with the item nil when the cursor is
      #   off-content.
      def cursor_state
        pos = @cursor.position
        item = pos >= 0 && pos < @items.size ? @items[pos] : nil
        [pos, item]
      end

      # Fires {#on_cursor_changed} if {#cursor_state} differs from the last
      # fired state. Idempotent — safe to call after any mutation.
      # @return [void]
      def notify_cursor_changed
        state = cursor_state
        return if state == @last_cursor_state

        @last_cursor_state = state
        @on_cursor_changed&.call(*state)
      end

      # @param query [String]
      # @param include_current [Boolean]
      # @param reverse [Boolean]
      # @return [Boolean]
      def search_and_go(query, include_current:, reverse:)
        return false if query.empty?

        candidates = @cursor.candidate_positions(@items.size)
        return false if candidates.empty?

        ordered = order_for_search(candidates, @cursor.position, include_current: include_current, reverse: reverse)
        query_lc = query.downcase
        match = ordered.find { |idx| render(@items[idx]).to_s.downcase.include?(query_lc) }
        return false unless match

        @cursor.go(match)
        move_viewport_to_cursor
        notify_cursor_changed
        invalidate
        true
      end

      # Rotates `candidates` (sorted ascending) so iteration starts from the
      # position appropriate for "find next" / "find prev" with optional
      # inclusion of the current.
      # @param candidates [Array<Integer>]
      # @param current [Integer]
      # @param include_current [Boolean]
      # @param reverse [Boolean]
      # @return [Array<Integer>]
      def order_for_search(candidates, current, include_current:, reverse:)
        if reverse
          before, after = if include_current
                            [candidates.select { _1 <= current }, candidates.select { _1 > current }]
                          else
                            [candidates.select { _1 < current }, candidates.select { _1 >= current }]
                          end
          before.reverse + after.reverse
        else
          after, before = if include_current
                            [candidates.select { _1 >= current }, candidates.select { _1 < current }]
                          else
                            [candidates.select { _1 > current }, candidates.select { _1 <= current }]
                          end
          after + before
        end
      end

      # Scrolls the viewport so the cursor is visible.
      # @return [void]
      def move_viewport_to_cursor
        pos = @cursor.position
        return unless pos >= 0

        if @top_line > pos
          self.top_line = pos
        elsif pos > @top_line + rect.height - 1
          self.top_line = pos - rect.height + 1
        end
      end

      # @return [Integer] the max value of {#top_line}.
      def top_line_max = (@items.size - rect.height).clamp(0, nil)

      # @return [Boolean] whether the viewport is pinned to the last line.
      #   Drives {#following?}: re-evaluated on every {#top_line=}.
      def at_bottom? = @top_line == top_line_max

      # @return [Integer] the number of visible lines.
      def viewport_lines = rect.height

      # Scrolls the list.
      # @param delta [Integer] negative scrolls up, positive scrolls down.
      # @return [void]
      def move_top_line_by(delta)
        new_top_line = (@top_line + delta).clamp(0, top_line_max)
        return if @top_line == new_top_line

        @top_line = new_top_line
        invalidate
      end

      # If auto-scrolling, recalculate the top line and snap the cursor to the
      # last reachable position. Without the cursor snap the viewport gets
      # yanked back to wherever the cursor sat on the next arrow press,
      # negating the auto-scroll. Skipped when {#rect} is empty: without a
      # viewport the "items minus viewport" formula yields `@items.size`,
      # which would leave `top_line` past the last item once a real rect
      # arrives. {#on_width_changed} re-runs this hook when the rect grows so
      # the snap-to-bottom intent is preserved.
      #
      # Gated on {#following?}: once the user scrolls up off the bottom the
      # cursor snap and viewport pin are both skipped, so reading older
      # content is not interrupted by incoming lines. {#top_line=} re-arms
      # `@follow` when the viewport returns to the bottom.
      # @return [void]
      def update_top_line_if_auto_scroll
        return unless @auto_scroll && @follow
        return if rect.empty?

        notify_cursor_changed if @cursor.go_to_last(@items.size)

        new_top_line = (@items.size - viewport_lines).clamp(0, nil)
        return unless @top_line != new_top_line

        self.top_line = new_top_line
      end

      # @return [Boolean] whether the scrollbar should be drawn right now.
      def scrollbar_visible?
        return false if rect.empty?

        @scrollbar_visibility == :visible
      end

      # @return [Integer] column width available for line content (rect width
      #   minus the scrollbar gutter, when visible). `0` when {#rect}'s width
      #   is non-positive.
      def content_width
        return 0 if rect.width <= 0

        rect.width - (scrollbar_visible? ? 1 : 0)
      end

      # Discards every rendered row, so the next paint re-renders the viewport
      # against the current items, renderer and width.
      # @return [void]
      def drop_row_cache
        @row_cache.clear
        @blank_row = nil
      end

      # @param index [Integer] 0-based index into {#items}.
      # @return [StyledString] the item's padded row, rendered on first use and
      #   memoized until {#drop_row_cache}.
      def padded_row(index)
        @row_cache[index] ||= pad_to_row(render(@items[index]))
      end

      # @return [StyledString] the blank row painted past the last item.
      def blank_row
        @blank_row ||= pad_to_row(StyledString::EMPTY)
      end

      # Renders one item, *without* populating the row cache — {#search_and_go}
      # scans with this, and caching a failed scan would grow the cache to one
      # row per item.
      # @param item [Object]
      # @return [StyledString] one row: the {#renderer}'s output coerced to a
      #   {StyledString}, cut to its first line since a `\n` reaching the buffer
      #   would corrupt the frame.
      def render(item)
        rendered = @renderer.call(item)
        rendered = StyledString.parse(rendered.to_s) unless rendered.is_a?(StyledString)
        return rendered unless rendered.spans.any? { _1.text.include?("\n") }

        rendered.lines.first
      end

      # Pads `line` to one full row of the viewport (scrollbar gutter
      # excluded). Lines wider than the content area are ellipsized via
      # {StyledString#ellipsize} (span styles survive the cut); shorter
      # lines are padded with default-styled spaces.
      # @param line [StyledString]
      # @return [StyledString] exactly {#content_width} display columns wide
      #   (or {StyledString::EMPTY} when content_width is non-positive).
      def pad_to_row(line)
        cw = content_width
        return StyledString::EMPTY if cw <= 0
        return StyledString.plain(" " * cw) if cw < 2

        text_width = cw - 2
        body = line.ellipsize(text_width)
        fill = cw - 2 - body.display_width
        StyledString.plain(" ") + body + StyledString.plain(" " * (fill + 1))
      end

      # @param index [Integer] 0-based index into {#items}.
      # @param row_in_viewport [Integer] 0-based row within the viewport.
      # @param scrollbar [VerticalScrollBar, nil] scrollbar instance, or nil
      #   if not shown.
      # @return [StyledString] paintable row exactly `rect.width` columns wide;
      #   highlighted if cursor is here.
      def paintable_row(index, row_in_viewport, scrollbar)
        base = index < @items.size ? padded_row(index) : blank_row
        is_cursor = (active? || @show_cursor_when_inactive) && index < @items.size && @cursor.position == index
        styled = is_cursor ? base.with_bg(screen.theme.active_bg_color) : base
        styled += StyledString.plain(scrollbar.scrollbar_char(row_in_viewport)) if scrollbar
        styled
      end
    end
  end
end
