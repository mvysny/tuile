# frozen_string_literal: true

module Tuile
  class Component
    # A one-row strip of captions with exactly one of them selected — the map of
    # where the user is. Knows nothing about content: pair it with
    # {Component::TabSheet} to swap panes, or swap views yourself from
    # {#on_tab_selected}.
    #
    #   ␣Details␣│␣Payment␣│␣Shipping␣
    #    ^^^^^^^   selected: bold, and highlighted while the strip has focus
    #
    #   tabs = Component::Tabs.new
    #   tabs.add_tab("Details")                # the first tab is selected
    #   payment = tabs.add_tab("Payment")
    #   tabs.on_tab_selected = ->(index, tab) { show(index) }
    #   tabs.selected = payment                # fires the listener
    #   payment.caption = "Payment ⚠"          # repaints the strip
    #
    # LEFT / RIGHT switch tabs immediately — no cursor to move first, no Enter
    # to confirm — clamping at both ends rather than wrapping; a left click
    # selects the tab under the pointer. Everything else bubbles to an ancestor,
    # Enter, Space, Up, Down, Home and End included, so a form's default button
    # and the app's own keys keep working while the strip has focus.
    #
    # One tab stop for the whole strip: Tab moves *past* it, never between its
    # tabs. For a key of your own that switches tabs from elsewhere in the app,
    # bind it yourself and call {#select_next} / {#select_previous}.
    #
    # {Tab} handles are minted by {#add_tab} and owned by the strip. There is no
    # `items=`: a tab is identity plus its own state, so the set grows and
    # shrinks one tab at a time. See book ch7 and `DECISIONS.md` `D-tabs`.
    #
    # == Sizing
    # Assign a {#rect} (typically from the surrounding {Layout}). One wider than
    # {#extent}`.width` leaves a dead tail; a narrower one **scrolls**. The strip
    # keeps the selected segment whole in view, moving its window by the minimum
    # needed, so arrowing into an off-screen tab brings that tab on screen — and
    # a click on a half-visible segment at an edge selects it and pulls it into
    # view. A `<` or `>` painted over an edge column says there is more strip
    # that way, as does the cut caption underneath it. The one thing that cannot
    # be shown whole is a caption wider than the entire rect: it shows its head
    # and clips its tail. The scroll offset itself is not API — the invariant is.
    #
    # == Implementation details
    # A segment is one space of padding, the caption, one space of padding, and
    # segments are joined by a single {DEFAULT_SEPARATOR} column. The padding
    # belongs to the segment: the highlight covers it and a click on it selects
    # the tab, while the separator column is chrome and selects nothing, like
    # the blank tail past {#extent}. One private `segments` method is the sole
    # source of that arithmetic — both the paint and the hit test read it, and
    # both offset it by the same scroll column, so a click cannot land on a tab
    # other than the one drawn under it — and it is
    # derived from the captions on each call rather than recorded during the
    # last paint, so a hit test is correct before the first paint.
    #
    # The selected caption is bold *always*, so the strip still says where you
    # are once focus has moved on, and additionally sits on
    # {Theme#active_bg_color} while the strip is on the focus chain. Bold is the
    # selection channel and not strip chrome: bolding every caption would leave
    # selection to the focus-gated background alone, and an unfocused strip
    # would then show no selection at all.
    class Tabs < Component
      # A single tab: a caption, plus its identity on the strip.
      #
      #   tab = tabs.add_tab("Payment")
      #   tab.caption = "Payment ⚠"   # repaints the strip
      #   tab.remove                  # `tab` now raises on every mutator
      #
      # Apps don't construct tabs; {Tabs#add_tab} mints them. A removed handle
      # raises {RuntimeError} on every mutator and on every reader that consults
      # the strip — answering confidently about a tab the strip no longer holds
      # would hide the bug. {#caption} and {#attached?} stay readable (the
      # caption lives here, so an error message can still name it), and
      # {#remove} is a silent no-op so a cleanup path can call it blindly.
      class Tab
        # @param strip [Tabs] the owning strip.
        # @param caption [StyledString] already coerced by the caller.
        def initialize(strip, caption)
          @strip = strip
          @caption = caption
        end

        private_class_method :new

        # @return [StyledString] the label painted on the strip. Safe to read on
        #   a removed tab.
        attr_reader :caption

        # Sets the caption and repaints the strip; no-op when unchanged.
        #
        # The caption is app-authored content and may carry its own colors — a
        # badge, a warning marker — over which the strip's own styling composes.
        # @param new_caption [String, StyledString, nil] parsed as
        #   {StyledString.parse} parses it; `nil` empties the caption.
        # @raise [RuntimeError] when the tab has been removed.
        # @return [void]
        def caption=(new_caption)
          check_attached
          new_caption = StyledString.parse(new_caption)
          return if @caption == new_caption

          @caption = new_caption
          @strip.send(:refresh)
        end

        # @return [Boolean] `true` while the tab is owned by its {Tabs}; `false`
        #   permanently once removed.
        def attached? = !@strip.nil?

        # @return [Boolean] whether this is the strip's selected tab.
        # @raise [RuntimeError] when the tab has been removed.
        def selected?
          check_attached
          @strip.selected.equal?(self)
        end

        # Removes this tab from its strip and detaches the handle permanently —
        # {Tabs#remove_tab} has what that does to the selection. Idempotent on an
        # already-removed tab, unlike the mutators.
        # @return [void]
        def remove
          return unless attached?

          @strip.remove_tab(self)
        end

        # @return [String]
        def inspect = "#<#{self.class.name} #{caption.to_s.inspect}#{attached? ? "" : " (removed)"}>"

        private

        # @return [void]
        def detach
          @strip = nil
        end

        # @raise [RuntimeError] when the tab has been removed.
        # @return [void]
        def check_attached
          raise "tab has been removed" unless attached?
        end
      end

      # The column between two segments — the glyph {Component::Window} paints
      # its side borders with, so a strip inside a window lines up with it.
      # @return [String]
      DEFAULT_SEPARATOR = "│"

      # Called on every change of {#selected} with the new selection —
      # `(index, tab)`, or `(nil, nil)` once the last tab has been removed.
      #
      # It reports that the selection *changed*, not that the user pressed
      # something: arrows, a click, {#selected=} / {#selected_index=}, the
      # autoselect of the first {#add_tab} and the re-selection that follows
      # removing the selected tab all fire it. Re-selecting the tab already
      # selected fires nothing.
      # @return [Proc, nil]
      attr_accessor :on_tab_selected

      # @param separator [String, StyledString] see {#separator=}.
      def initialize(separator: DEFAULT_SEPARATOR)
        super()
        @tabs = []
        @selected_index = nil
        @left_column = 0
        self.separator = separator
      end

      # @return [Boolean] `true` — the strip takes focus, so its arrows work.
      def focusable? = true

      # @return [Boolean] `true` — one stop for the whole strip.
      def tab_stop? = true

      # @return [Array<Tab>] the tabs, in strip order. Read-only by convention
      #   (like {Component#children}) — grow and shrink it through {#add_tab} /
      #   {#remove_tab}, which keep the selection consistent. Enumerate it to
      #   find a tab: `tabs.find { |t| t.caption.to_s == "Payment" }`.
      attr_reader :tabs

      # @return [StyledString] the column painted between two segments.
      attr_reader :separator

      # @param new_separator [String, StyledString] e.g. ASCII `"|"` for a
      #   terminal that renders `│` badly. Both the paint and the hit test
      #   measure it, so a wider one widens the dead column between segments.
      # @raise [ArgumentError] when empty — adjacent captions would run
      #   together.
      # @return [void]
      def separator=(new_separator)
        new_separator = StyledString.parse(new_separator)
        raise ArgumentError, "separator must not be empty" if new_separator.empty?
        return if @separator == new_separator

        @separator = new_separator
        refresh
      end

      # @return [Tab, nil] the selected tab; `nil` only while there are no tabs.
      def selected = @selected_index && @tabs[@selected_index]

      # @return [Integer, nil] the selected tab's position; `nil` only while
      #   there are no tabs.
      attr_reader :selected_index

      # @param tab [Tab] one of this strip's tabs.
      # @raise [ArgumentError] when the tab isn't on this strip (a removed one
      #   never is).
      # @return [void]
      def selected=(tab)
        select_at(index_of!(tab))
      end

      # Selects the tab at `index`. There is deliberately no way to select
      # *nothing* while tabs exist — a strip showing captions with none of them
      # selected has no meaning, and a {Component::TabSheet} in that state would
      # show no pane.
      # @param index [Integer] a position in `0...tabs.size`.
      # @raise [TypeError] when `index` isn't an `Integer`.
      # @raise [ArgumentError] when `index` is out of range.
      # @return [void]
      def selected_index=(index)
        raise TypeError, "expected Integer, got #{index.inspect}" unless index.is_a?(Integer)
        unless (0...@tabs.size).cover?(index)
          raise ArgumentError, "index #{index} out of range for #{@tabs.size} tab(s)"
        end

        select_at(index)
      end

      # Appends a tab and returns its handle. The first tab added becomes the
      # selection; later ones don't disturb it.
      # @param caption [String, StyledString, nil] parsed as {Tab#caption=}
      #   parses it.
      # @return [Tab]
      def add_tab(caption = nil)
        tab = Tab.send(:new, self, StyledString.parse(caption))
        @tabs << tab
        @selected_index.nil? ? select_at(0) : refresh
        tab
      end

      # Removes `tab` and detaches its handle permanently.
      #
      # The selection is never left dangling: removing the selected tab selects
      # whichever tab slid into its place (the new last tab, if it was the last),
      # and removing the final tab leaves {#selected} `nil`. Either way
      # {#on_tab_selected} fires — the empty case with `(nil, nil)`, since a
      # listener rendering from the selection has to be told to render nothing.
      # @param tab [Tab] one of this strip's tabs.
      # @raise [ArgumentError] when the tab isn't on this strip.
      # @return [void]
      def remove_tab(tab)
        index = index_of!(tab)
        previous = selected
        @tabs.delete_at(index)
        tab.send(:detach)
        apply_selection(selection_after_removing(index), previous)
      end

      # Selects the next tab, clamping at the last — the strip never wraps.
      # Public because it is the verb an app's own key binding drives.
      # @return [Boolean] `false` only when there are no tabs.
      def select_next = step_selection(1)

      # Selects the previous tab, clamping at the first.
      # @return [Boolean] `false` only when there are no tabs.
      def select_previous = step_selection(-1)

      # The cells the strip actually paints: one row, as wide as its segments and
      # separators need, clipped to {#rect}. A layout routinely hands a strip a
      # window's full width for a 32-column strip — the extent is those 32
      # columns.
      #
      # Both the focus highlight and the click hit test use it, so a click on the
      # blank tail — or on a lower row, when the rect is taller than one —
      # selects nothing. It still *focuses*: {Component#handle_mouse}'s
      # click-to-focus is ungated by geometry.
      # @return [Rect]
      def extent
        return Rect.new(rect.left, rect.top, 0, 1) if rect.empty?

        Rect.new(rect.left, rect.top, [painted_width - @left_column, rect.width].min, 1)
      end

      # @return [String]

      # Switches tabs on LEFT / RIGHT, consuming the key even at the ends of the
      # strip (the selection clamps). Every other key is left unhandled so it
      # bubbles to an ancestor; an empty strip handles nothing at all.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        case key
        when Keys::LEFT_ARROW then select_previous
        when Keys::RIGHT_ARROW then select_next
        else false
        end
      end

      # Selects the tab under a left click; `super` runs first, so a click
      # anywhere in {#rect} still focuses.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left

        tab = tab_at(event.point)
        self.selected = tab if tab
      end

      # @return [void]
      def repaint
        super
        return if rect.empty?

        row = strip_row.slice(@left_column, rect.width)
        draw_text(rect.left, rect.top, row)
        draw_cues(row)
      end

      private

      # @return [Integer] the strip column painted in {#rect}'s leftmost cell —
      #   the horizontal scroll offset. `0` unless the strip overflows its rect;
      #   {#adjust_left_column} is its sole writer.
      attr_reader :left_column

      # Re-syncs the scroll offset and repaints — what every change to the
      # captions, the separator or the selection ends in.
      # @return [void]
      def refresh
        adjust_left_column
        invalidate
      end

      # The rect's *width* is the only part of it the offset depends on, so this
      # hook is the whole geometry story; {Component#rect=} invalidates for us.
      # @return [void]
      def on_width_changed
        super
        adjust_left_column
      end

      # Scrolls the minimum needed to show the selected segment whole, and is the
      # sole writer of {#left_column}. Idempotent, so every mutation site can
      # call it blindly; it returns the offset to `0` on its own once the strip
      # fits again, which is why no mutator owes a scroll-back branch.
      #
      # A segment wider than the whole rect cannot be shown whole: its head wins,
      # being the half of a caption that identifies it.
      # @return [void]
      def adjust_left_column
        if rect.empty? || painted_width <= rect.width || @selected_index.nil?
          @left_column = 0
          return
        end

        _tab, start, width = segments[@selected_index]
        if width >= rect.width
          @left_column = start
        else
          @left_column = start if start < @left_column
          @left_column = start + width - rect.width if start + width > @left_column + rect.width
        end
        @left_column = snap_to_glyph_start(@left_column.clamp(0, painted_width - rect.width))
      end

      # {StyledString#slice} *drops* a cluster straddling the window's edge
      # rather than half-painting it, which would leave the painted row a column
      # short and shift everything past the hole one column left — paint and hit
      # test would then disagree, silently and only for wide glyphs. So the
      # offset only ever lands on a cluster boundary. Snapping *forward* is the
      # safe direction: it gives up at most one column of the segment to the left
      # of the window, never of the one being revealed.
      # @param column [Integer]
      # @return [Integer] the smallest cluster-boundary column `>= column`.
      def snap_to_glyph_start(column)
        boundary = 0
        strip_row.to_s.each_grapheme_cluster do |glyph|
          return boundary if boundary >= column

          boundary += Buffer.display_width(glyph)
        end
        boundary
      end

      # Paints the overflow cues over the windowed row's edge columns: `<` when
      # segments sit to the left of the window, `>` when more sit to the right.
      # ASCII by convention rather than by constant, as {Checkbox}'s brackets
      # are, and *overlaid* rather than given reserved columns — reserving would
      # make the window width a function of the offset computed from it.
      # @param row [StyledString] the windowed row, as painted.
      # @return [void]
      def draw_cues(row)
        draw_cue(row, 0, "<") if @left_column.positive?
        draw_cue(row, rect.width - 1, ">") if @left_column + rect.width < painted_width
      end

      # The cue keeps the style of the cell it covers, so one landing on the
      # selected segment doesn't punch a default-background hole in its
      # highlight.
      # @param row [StyledString] the windowed row.
      # @param column [Integer] relative to {#rect}`.left`.
      # @param glyph [String]
      # @return [void]
      def draw_cue(row, column, glyph)
        style = row.slice(column, 1).spans.first&.style || StyledString::Style::DEFAULT
        draw_char(rect.left + column, rect.top, glyph, style)
      end

      # One `[tab, start_column, width]` triple per tab, in strip order, in
      # columns relative to {#rect}`.left`. A segment's width is its caption plus
      # the two padding columns; the separator columns between segments belong to
      # no segment.
      # @return [Array<Array(Tab, Integer, Integer)>]
      def segments
        column = 0
        @tabs.each_with_index.map do |tab, index|
          column += separator.display_width if index.positive?
          width = tab.caption.display_width + 2
          [tab, column, width].tap { column += width }
        end
      end

      # @return [Integer] columns the strip would paint given an unlimited rect.
      def painted_width
        _tab, start, width = segments.last
        start.nil? ? 0 : start + width
      end

      # @param point [Point]
      # @return [Tab, nil] the tab painted at `point`; `nil` for a separator
      #   column, the blank tail, or a row the strip doesn't paint.
      def tab_at(point)
        return nil unless extent.contains?(point)

        column = point.x - rect.left + @left_column
        found = segments.find { |_tab, start, width| column >= start && column < start + width }
        found&.first
      end

      # @return [StyledString] the whole strip as one row, unclipped: segments
      #   left to right, joined by the separator. {#repaint} windows it to the
      #   rect; nothing else may, since the window's own arithmetic is
      #   {#adjust_left_column}'s.
      def strip_row
        row = StyledString::EMPTY
        @tabs.each_with_index do |tab, index|
          row += separator if index.positive?
          row += segment_text(tab, index)
        end
        row
      end

      # @param tab [Tab]
      # @param index [Integer]
      # @return [StyledString] the caption between its padding columns, styled
      #   for the selection.
      def segment_text(tab, index)
        pad = StyledString.plain(" ")
        segment = pad + tab.caption + pad
        return segment unless index == @selected_index

        segment = segment.with_bold
        active? ? segment.with_bg(screen.theme.active_bg_color) : segment
      end

      # @param tab [Tab]
      # @return [Integer] the tab's position on this strip.
      # @raise [ArgumentError] when it isn't on this strip.
      def index_of!(tab)
        index = @tabs.index { |candidate| candidate.equal?(tab) }
        raise ArgumentError, "not a tab of this strip: #{tab.inspect}" if index.nil?

        index
      end

      # @param delta [Integer] `+1` / `-1`.
      # @return [Boolean] `false` only when there are no tabs.
      def step_selection(delta)
        return false if @tabs.empty?

        select_at((@selected_index + delta).clamp(0, @tabs.size - 1))
        true
      end

      # @param index [Integer, nil]
      # @return [void]
      def select_at(index)
        apply_selection(index, selected)
      end

      # Stores the selection, repaints, and fires {#on_tab_selected} when the
      # selected *tab* changed.
      #
      # `previous` is passed in rather than read here because a removal can leave
      # the index numerically unchanged while a different tab sits under it —
      # remove the selected middle tab of three and index 1 now holds what used
      # to be index 2. Comparing indices would swallow that notification.
      # @param index [Integer, nil] the new selection.
      # @param previous [Tab, nil] the tab selected before the caller's change.
      # @return [void]
      def apply_selection(index, previous)
        @selected_index = index
        refresh
        tab = index.nil? ? nil : @tabs[index]
        return if tab.equal?(previous)

        @on_tab_selected&.call(index, tab)
      end

      # Called with `@tabs` already shortened and `@selected_index` still holding
      # the pre-removal position.
      # @param removed_index [Integer] the position the removed tab held.
      # @return [Integer, nil] where the selection lands.
      def selection_after_removing(removed_index)
        return nil if @tabs.empty?
        return @selected_index if removed_index > @selected_index
        return @selected_index - 1 if removed_index < @selected_index

        [removed_index, @tabs.size - 1].min
      end
    end
  end
end
