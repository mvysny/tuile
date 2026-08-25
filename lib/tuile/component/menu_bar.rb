# frozen_string_literal: true

module Tuile
  class Component
    # A one-row strip of menu captions, each dropping open a cascade of submenus
    # that nests as deep as you build it.
    #
    #   ␣File␣␣Edit␣␣View␣          <- the strip; highlighted while focused
    #    ␣New␣␣␣␣␣␣␣␣␣              <- the open menu, measured to its widest label
    #    ␣Recent␣␣␣␣▸␣              <- a row that opens a submenu
    #    ␣Quit␣␣␣␣␣␣␣␣              (the outer gutters are {List}'s)
    #
    #   bar = Component::MenuBar.new
    #   file = bar.add_item("File", mnemonic: "f")
    #   file.add_item("New", mnemonic: "n") { new_document }
    #   recent = file.add_item("Recent")            # no block ⇒ a submenu holder
    #   recent.add_item("notes.txt") { open("notes.txt") }
    #   bar.add_item("Quit") { screen.close }       # a top-level leaf: a button
    #
    # LEFT / RIGHT move along the strip; Enter, Space or Down opens the
    # highlighted menu. Inside a menu: Up / Down (and PgUp/PgDn, Ctrl+U/D) move
    # the highlight, Enter or Space activates a row or opens its submenu, RIGHT
    # opens a submenu, LEFT returns to the previous menu, ESC closes one level.
    # LEFT at the first level and RIGHT on a row with no submenu step to the
    # sibling menu, as they do in every menu bar. Book ch7 has the table.
    #
    # == Mnemonics
    # An item given a `mnemonic:` answers to that letter, underlined in its
    # caption wherever it occurs — on the strip and in the panels, focused or
    # not (there is no Alt key to reveal them with). Matching is **level-scoped
    # with no fallback**: the top-level items while the cascade is closed, the
    # deepest open panel's items while it is open, and nothing else is ever
    # consulted. So `f` then `q` walks File ▸ Quit as two ordinary keystrokes,
    # two items on *different* levels may share a letter with nothing to
    # arbitrate, and only siblings compete — a duplicate among them raises at
    # {#add_item}. A letter matching nothing on the live level is swallowed and
    # rings {Screen#beep}; it never falls out to a shallower level and switches
    # menus. A mnemonic shadows what the app (or an ancestor, including a
    # {Popup}'s `q`-to-close) would do with that key while the bar has focus.
    # A paste can never fire one — pasted text rides its own path off the key
    # ladder.
    #
    # {Item} handles are minted by {#add_item} and nest via the *same* method, so
    # depth is unlimited. There is no removal, no reordering and no dynamic
    # rebuilding: a menu is built once, at construction. See `DECISIONS.md`
    # `D-menu-bar`.
    #
    # == Sizing
    # Assign a {#rect} (typically one {Layout::Fixed}`[1]` row at the top of a
    # {Layout::Vertical}). One wider than {#extent}`.width` leaves a dead tail; a
    # narrower one **scrolls** to keep the highlighted segment whole, cueing the
    # hidden captions with a `<` or `>` over an edge column, exactly as {Tabs}
    # does — so a bar wider than its terminal stays wholly reachable by arrow,
    # mnemonic and click. Reassigning the rect
    # **closes** an open cascade: every panel position is derived from a segment
    # or a parent row, so after a resize they would all sit at stale columns, and
    # a resize with a menu open is rare enough that closing beats re-anchoring
    # every level.
    #
    # == Implementation details
    # Deliberately painted *unlike* {Tabs}, whose picture it would otherwise
    # share: no separator between segments, no bold, and no highlight at all
    # while unfocused — a menu bar has no persistent selection to show, and a
    # reader should not have to work out which of the two controls they are
    # looking at. Hit testing *is* {Tabs}': one private `segments` method feeds
    # both the paint and the click and both offset it by the same scroll column,
    # so a click cannot land on a caption other than the one drawn under it, and it is derived from the captions on each
    # call so a hit test is correct before the first paint.
    #
    # The open panels are overlays owned by a private {Cascade}, not children:
    # focus stays here for the whole interaction, so the strip receives every key
    # and forwards it. An open cascade swallows keys the cascade doesn't
    # recognize; a *closed* strip lets every printable bubble, so an app's
    # `s`-to-save keeps working while the bar has focus.
    #
    # A click outside an open cascade is not blocked — non-modal overlays block
    # nothing — but any click on a focusable component moves focus, and losing
    # focus closes the cascade.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class MenuBar < Component
      # One menu item: a caption, an optional click listener, and its children.
      #
      #   file = bar.add_item("File")       # minted by the bar
      #   file.add_item("New") { create }   # …and nested by the same method
      #   file.items.size                   # => 1
      #
      # An item with children is a submenu and its own listener is dead
      # ({#submenu?} decides). An item with **neither** children nor a listener is
      # legal and inert: it highlights, Enter closes the menu, nothing happens —
      # an item that looks live but does nothing is the app's error to fix, not
      # the framework's to raise on.
      #
      # Apps don't construct items; {MenuBar#add_item} and {#add_item} do.
      class Item
        # @param caption [StyledString] already coerced by the caller.
        # @param mnemonic [String, nil] already validated by the caller, in the
        #   case it was given in.
        # @param on_click [Proc, Method, nil]
        def initialize(caption, mnemonic, on_click)
          @caption = caption
          @mnemonic = mnemonic&.downcase
          @cued_caption = build_cued_caption(caption, mnemonic)
          @on_click = on_click
          @items = []
        end

        private_class_method :new

        # @return [StyledString] the label painted on the strip or the row.
        attr_reader :caption

        # @return [String, nil] the downcased letter that activates this item
        #   while its own level is the live one; `nil` when it has none.
        attr_reader :mnemonic

        # @return [StyledString] {#caption} with the {#mnemonic} underlined —
        #   what both paint sites draw. Equal to {#caption} when there is no
        #   mnemonic or the caption doesn't contain it. Computed once, at
        #   construction: caption and mnemonic are both fixed there, and
        #   underline is a plain attribute with no theme or `bg_color` input, so
        #   this is not a cached theme value.
        attr_reader :cued_caption

        # @return [Array<Item>] this item's children, in menu order. Read-only by
        #   convention, like {Component#children} — grow it through {#add_item}.
        attr_reader :items

        # @return [Proc, Method, nil] no-arg callable fired when the item is
        #   activated (Enter, Space or a left click), exactly as
        #   {Button#on_click}. Never fired on an item with children.
        attr_accessor :on_click

        # @return [Boolean] whether this item opens a submenu, i.e. has children.
        def submenu? = !@items.empty?

        # Appends a child and returns its handle.
        # @param caption [String, StyledString, nil] parsed as
        #   {StyledString.parse} parses it.
        # @param mnemonic [String, nil] the letter that activates this child
        #   while *this* item's children are the live level; see
        #   {MenuBar#add_item}.
        # @yield optional `on_click` callback; same as assigning {#on_click=}.
        # @raise [ArgumentError] see {MenuBar#add_item}.
        # @return [Item]
        def add_item(caption = nil, mnemonic: nil, &on_click)
          validate_mnemonic(mnemonic)
          Item.send(:new, StyledString.parse(caption), mnemonic, on_click).tap { @items << _1 }
        end

        # @return [String]
        def inspect
          mn = @mnemonic.nil? ? "" : " [#{@mnemonic}]"
          "#<#{self.class.name} #{caption.to_s.inspect}#{mn}#{submenu? ? " (#{@items.size} items)" : ""}>"
        end

        private

        # Rejects a mnemonic that couldn't work, or that would make two siblings
        # ambiguous — all three at *registration*, since none has a sane answer
        # at keypress time.
        # @param mnemonic [String, nil]
        # @raise [ArgumentError]
        # @return [void]
        def validate_mnemonic(mnemonic)
          return if mnemonic.nil?

          # Not implied by printable?, which accepts " ".
          raise ArgumentError, "mnemonic must not be a space: Space activates the highlighted item" if mnemonic == " "
          unless Keys.printable?(mnemonic) && StyledString.plain(mnemonic).display_width == 1
            raise ArgumentError, "mnemonic must be a single one-column printable character; got #{mnemonic.inspect}"
          end

          down = mnemonic.downcase
          return unless @items.any? { |item| item.mnemonic == down }

          raise ArgumentError, "duplicate mnemonic #{down.inspect} among these menu items"
        end

        # {StyledString#slice} counts **columns** while a caption search yields a
        # **character** index, so the prefix is measured, never counted.
        # @param caption [StyledString]
        # @param mnemonic [String, nil] in the case it was given in.
        # @return [StyledString]
        def build_cued_caption(caption, mnemonic)
          return caption if mnemonic.nil?

          text = caption.to_s
          # Exact case first, so "Save As" can underline either "a" via the case
          # it was given in.
          index = text.index(mnemonic) || text.downcase.index(mnemonic.downcase)
          return caption if index.nil?

          start = StyledString.plain(text[0, index]).display_width
          caption.slice(0, start) + caption.slice(start, 1).with_underline +
            caption.slice(start + 1, caption.display_width - start - 1)
        end
      end

      def initialize
        super()
        @root = Item.send(:new, StyledString::EMPTY, nil, nil)
        @highlighted_index = 0
        @left_column = 0
        @cascade = Cascade.new
      end

      # @return [Boolean] `true` — the strip takes focus, so its keys work.
      def focusable? = true

      # @return [Boolean] `true` — one stop for the whole strip, as on {Tabs}.
      def tab_stop? = true

      # @return [Array<Item>] the top-level items, in strip order. Read-only by
      #   convention; grow it through {#add_item}.
      def items = @root.items

      # @return [Integer] which top-level item the strip highlights while
      #   focused, and which menu Enter opens. `0` until the user moves.
      attr_reader :highlighted_index

      # Appends a top-level item and returns its handle; nest submenus into it
      # with {Item#add_item}.
      # @param caption [String, StyledString, nil] parsed as
      #   {StyledString.parse} parses it.
      # @param mnemonic [String, nil] a single one-column printable character
      #   that activates this item while the strip is focused and *closed*,
      #   underlined in the caption where it occurs. Matched case-insensitively;
      #   it shadows whatever the app would otherwise do with that key while the
      #   bar has focus.
      # @yield optional `on_click` callback, for a top-level item that acts as a
      #   button rather than opening a menu.
      # @raise [ArgumentError] if `mnemonic` is a space, is not a single
      #   one-column printable character, or duplicates a sibling's.
      # @return [Item]
      def add_item(caption = nil, mnemonic: nil, &on_click)
        @root.add_item(caption, mnemonic: mnemonic, &on_click).tap { refresh }
      end

      # The cells the strip actually paints: one row, as wide as its segments
      # need, clipped to {#rect}.
      #
      # Both the highlight and the click hit test use it, so a click on the blank
      # tail — or on a lower row, when the rect is taller than one — opens
      # nothing. It still *focuses*: {Component#handle_mouse}'s click-to-focus is
      # ungated by geometry.
      # @return [Rect]
      def extent
        return Rect.new(rect.left, rect.top, 0, 1) if rect.empty?

        Rect.new(rect.left, rect.top, [painted_width - @left_column, rect.width].min, 1)
      end

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        # Only a *changed* rect closes the menu: a layout re-assigning the same
        # rect (which {Layout::Box} does on any child mutation) must not.
        changed = rect != new_rect
        super
        @cascade.close if changed
      end

      # Closes the cascade when the strip leaves the focus chain, so tabbing (or
      # clicking) away doesn't strand an open menu.
      # @param flag [Boolean]
      # @return [void]
      def active=(flag)
        was = active?
        super
        @cascade.close if was && !active?
      end

      # Closes the cascade, so a bar removed from the tree can't strand its
      # panels on the pane — they are the {ScreenPane}'s children, not the bar's,
      # so nothing else would take them down.
      # @return [void]
      def on_detached
        super
        @cascade.close
      end

      # Offers the key to the open cascade first, then to the strip's own
      # LEFT/RIGHT/Enter/Space/Down.
      #
      # With a cascade open, the only keys reaching the strip are the two the
      # cascade declines — LEFT at the first level, RIGHT on a row with no
      # submenu — and both step to the sibling menu.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        # Ahead of the cascade: an open one swallows every printable it doesn't
        # recognize, so a letter would never reach the strip otherwise.
        return true if handle_mnemonic(key)
        return true if @cascade.handle_key(key)

        if @cascade.open?
          case key
          when Keys::LEFT_ARROW then step_menu(-1)
          when Keys::RIGHT_ARROW then step_menu(1)
          else false
          end
        else
          case key
          when Keys::LEFT_ARROW then move_highlight(-1)
          when Keys::RIGHT_ARROW then move_highlight(1)
          when Keys::ENTER, " ", Keys::DOWN_ARROW then open_highlighted
          else false
          end
        end
      end

      # Opens the menu under a left click, or closes it when it is already the
      # open one; `super` runs first, so a click anywhere in {#rect} still
      # focuses.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left

        index = index_at(event.point)
        return if index.nil?

        if @cascade.open? && index == @highlighted_index
          @cascade.close
        else
          self.highlight = index
          open_highlighted
        end
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

      # The sole writer of {#highlighted_index}: assigns, re-syncs the scroll
      # offset and repaints. Every path that moves the highlight — arrow,
      # mnemonic, click — goes through it, so the highlighted segment is on
      # screen *before* {Cascade} anchors a panel to it.
      # @param index [Integer]
      # @return [void]
      def highlight=(index)
        return if index == @highlighted_index

        @highlighted_index = index
        refresh
      end

      # Re-syncs the scroll offset and repaints — what every change to the items
      # or the highlight ends in.
      # @return [void]
      def refresh
        adjust_left_column
        invalidate
      end

      # The rect's *width* is the only part of it the offset depends on, so this
      # hook is the whole geometry story; {Component#rect=} invalidates for us,
      # and {#rect=} closes the cascade rather than re-anchoring it.
      # @return [void]
      def on_width_changed
        super
        adjust_left_column
      end

      # Scrolls the minimum needed to show the highlighted segment whole, and is
      # the sole writer of {#left_column}. Idempotent, so every mutation site can
      # call it blindly; it returns the offset to `0` on its own once the strip
      # fits again, which is why no mutator owes a scroll-back branch.
      #
      # A segment wider than the whole rect cannot be shown whole: its head wins,
      # being the half of a caption that identifies it.
      # @return [void]
      def adjust_left_column
        if rect.empty? || painted_width <= rect.width || items.empty?
          @left_column = 0
          return
        end

        _item, start, width = segments[@highlighted_index]
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
      # make the window width a function of the offset computed from it. Painted
      # focused or not: overflow is a fact about the captions and the rect, not
      # about focus.
      # @param row [StyledString] the windowed row, as painted.
      # @return [void]
      def draw_cues(row)
        draw_cue(row, 0, "<") if @left_column.positive?
        draw_cue(row, rect.width - 1, ">") if @left_column + rect.width < painted_width
      end

      # The cue keeps the style of the cell it covers, so one landing on the
      # highlighted segment doesn't punch a default-background hole in its
      # highlight.
      # @param row [StyledString] the windowed row.
      # @param column [Integer] relative to {#rect}`.left`.
      # @param glyph [String]
      # @return [void]
      def draw_cue(row, column, glyph)
        style = row.slice(column, 1).spans.first&.style || StyledString::Style::DEFAULT
        draw_char(rect.left + column, rect.top, glyph, style)
      end

      # One `[item, start_column, width]` triple per top-level item, in strip
      # order, in columns relative to {#rect}`.left`. A segment is its caption
      # between two padding columns, and neighbours abut — the two blank columns
      # between captions are the segments' own padding, so a click on either
      # opens the menu it belongs to.
      # @return [Array<Array(Item, Integer, Integer)>]
      def segments
        column = 0
        items.map do |item|
          width = item.cued_caption.display_width + 2
          [item, column, width].tap { column += width }
        end
      end

      # @return [Integer] columns the strip would paint given an unlimited rect.
      def painted_width
        _item, start, width = segments.last
        start.nil? ? 0 : start + width
      end

      # @param point [Point]
      # @return [Integer, nil] the index of the item painted at `point`; `nil`
      #   for the blank tail or a row the strip doesn't paint.
      def index_at(point)
        return nil unless extent.contains?(point)

        column = point.x - rect.left + @left_column
        segments.index { |_item, start, width| column >= start && column < start + width }
      end

      # @param index [Integer]
      # @return [Rect] the segment's cells on screen — the cascade's anchor.
      def segment_rect(index)
        _item, start, width = segments[index]
        Rect.new(rect.left + start - @left_column, rect.top, width, 1)
      end

      # @return [StyledString] the whole strip as one row, unclipped. {#repaint}
      #   windows it to the rect; nothing else may, since the window's own
      #   arithmetic is {#adjust_left_column}'s.
      def strip_row
        row = StyledString::EMPTY
        items.each_with_index { |item, index| row += segment_text(item, index) }
        row
      end

      # @param item [Item]
      # @param index [Integer]
      # @return [StyledString] the caption between its padding columns,
      #   highlighted when it is the one Enter would open *and* the strip has
      #   focus. An unfocused strip shows no highlight at all: there is no
      #   persistent selection to report.
      def segment_text(item, index)
        pad = StyledString.plain(" ")
        segment = pad + item.cued_caption + pad
        return segment unless index == @highlighted_index && active?

        segment.with_bg(screen.theme.active_bg_color)
      end

      # Activates the item bound to `key` on the *live* level — the deepest open
      # panel while the cascade is open, the top-level strip while it is closed.
      # No fallback between the two: a letter matching nothing in the live set is
      # not offered to any other level.
      # @param key [String]
      # @return [Boolean] whether a mnemonic claimed the key.
      def handle_mnemonic(key)
        return false unless Keys.printable?(key)

        down = key.downcase
        return @cascade.handle_mnemonic(down) if @cascade.open?

        index = items.index { |item| item.mnemonic == down }
        return false if index.nil?

        self.highlight = index
        open_highlighted
      end

      # Moves the highlight along the strip, clamping at both ends. Consumes the
      # key even at an end, as {Tabs} does.
      # @param delta [Integer] `+1` / `-1`.
      # @return [Boolean] `false` only when there are no items.
      def move_highlight(delta)
        return false if items.empty?

        self.highlight = (@highlighted_index + delta).clamp(0, items.size - 1)
        true
      end

      # Steps to the neighbouring menu, showing *its* menu instead — or closing
      # the cascade, when the neighbour is a top-level button with no menu to
      # show. The cascade is left alone when the highlight is already at an end:
      # reopening the same menu would throw away the submenu the user is standing
      # in.
      #
      # It deliberately never *activates*. An item arrowed past is highlighted,
      # not pressed, so a top-level button waits for Enter or Space — otherwise
      # walking the strip would fire every button on it.
      # @param delta [Integer] `+1` / `-1`.
      # @return [Boolean] always `true`: an open menu swallows the key either way.
      def step_menu(delta)
        was = @highlighted_index
        move_highlight(delta)
        show_highlighted_menu unless @highlighted_index == was
        true
      end

      # Opens the highlighted item's menu, or fires it when it is a top-level
      # button — the Enter/Space/Down/click path, and the only one that fires a
      # listener.
      # @return [Boolean] `false` only when there are no items.
      def open_highlighted
        return false if items.empty?

        item = items[@highlighted_index]
        show_highlighted_menu
        # Fired after the close above, exactly as {Cascade} activates a leaf: an
        # action that opens a dialog must not paint it under a menu.
        item.on_click&.call unless item.submenu?
        true
      end

      # Shows the highlighted item's menu, closing the cascade when it has none.
      # @return [void]
      def show_highlighted_menu
        item = items[@highlighted_index]
        return @cascade.close unless item.submenu?

        @cascade.open_below(segment_rect(@highlighted_index), item)
      end
    end
  end
end
