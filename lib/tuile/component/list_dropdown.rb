# frozen_string_literal: true

module Tuile
  class Component
    # A borderless, tinted, non-focusable floating selection list — the dropdown
    # a *driver* drops open, drives by forwarding movement keys, and commits a
    # pick from: an {Overlay} wrapping a {List} that never takes focus, so
    # focus stays on the driver while the caller refills the rows, moves the
    # highlight, and reads the pick.
    #
    #   drop = Component::ListDropdown.new
    #   drop.renderer = method(:label_for)                 # caller renders
    #   drop.list.on_item_chosen { |e| commit(e.item) }    # caller commits
    #   # …then, from the driver's key handler:
    #   drop.items = matches                         # caller filters
    #   drop.anchor_to(self)                         # opens it below the driver, or flipped
    #   return true if drop.move(key)  # Up/Down/PgUp/PgDn/^U/^D → list scroll
    #   drop.choose if key == Keys::ENTER            # commit the highlight
    #
    # It owns only what every such dropdown shares — *placement* included, via
    # {#anchor_to} (below a field) and {#anchor_beside} (beside a parent row, for
    # a cascading submenu). What stays with the driver: the width **policy**
    # (neither placement method measures anything itself), filtering, row
    # rendering, the commit action, and ESC/Enter handling. ESC and Enter carry driver-specific tails (ESC may
    # revert a query; Enter may commit via {#choose} *or* via a separate submit
    # path), so {#move} claims neither — the driver calls {#choose} and {#close}
    # from its own branches.
    #
    # == Theming
    # Borderless, told apart from the content beneath by a background tint —
    # {Theme#input_bg_color} by default, assigned as a live {Theme::Ref} so it
    # tracks light/dark flips with no hook. Reassign {Component#bg_color=} for a
    # different tint (a `Theme.ref(:token)` keeps the flip-tracking).
    #
    # UI-thread-confined, like every component (see {Screen}).
    class ListDropdown < Overlay
      # The dropdown's {List}. Non-focusable on purpose: the driver forwards keys
      # while focus stays on it, and a mouse click selects an item without
      # stealing focus — so a driving text input never loses its caret
      # mid-interaction.
      class Menu < List
        def focusable? = false
        def tab_stop? = false
      end

      # Cursor-movement keys forwarded to the list by {#move}: the two vertical
      # arrows, page up/down, and Ctrl+U/D half-page jumps. Deliberately excludes
      # Home/End and `j`/`k` — a jump to the first/last row is the driver's call,
      # and both drivers decline it ({ComboBox}'s field needs Home/End for the
      # caret; {Select} would spend a branch on what a second arrow press already
      # does) — and Enter/ESC, which carry driver-specific tails (see the class
      # docs).
      #
      # A driver only ever sees the keys its own children decline, so a
      # {ComboBox} never gets Ctrl+U — its field claims it to clear the query —
      # while {Select}, wrapping no editor, gets every one of these.
      # @return [Array<String>]
      MOVE_KEYS = [Keys::UP_ARROW, Keys::DOWN_ARROW, Keys::PAGE_UP, Keys::PAGE_DOWN,
                   Keys::CTRL_U, Keys::CTRL_D].freeze

      # Most rows shown before the list scrolls; {#anchor_to}'s `max_rows`
      # default.
      # @return [Integer]
      MAX_VISIBLE_ROWS = 10

      # The placement {#anchor_to} and {#anchor_beside} open the dropdown with:
      # hung off `anchor`, `side` `:below` or `:beside` it, as tall as its rows
      # up to `max_rows`. The pane re-reads the anchor on every pass and again
      # once the content has settled, so the panel follows a field that moves.
      #
      # @!attribute [r] anchor
      #   @return [Component, Rect] a component, followed by its
      #     {Component#absolute_extent_rect}, or a fixed rect in screen
      #     coordinates.
      # @!attribute [r] side
      #   @return [Symbol] `:below` or `:beside`.
      # @!attribute [r] width
      #   @return [Integer, #call, nil] columns, or something answering them when
      #     called; `nil` takes the anchor's width.
      # @!attribute [r] max_rows
      #   @return [Integer] rows shown before the list scrolls.
      Anchored = Data.define(:anchor, :side, :width, :max_rows) do
        # @return [Rect, nil] the anchor in screen coordinates, or `nil` when a
        #   component anchor is detached or hidden.
        def anchor_rect
          return anchor if anchor.is_a?(Rect)

          node = anchor
          until node.nil?
            return nil unless node.visible?

            node = node.parent
          end
          anchor.attached? ? anchor.absolute_extent_rect : nil
        end

        # @param drop [ListDropdown]
        # @param screen_size [Size]
        # @return [Rect]
        def rect_for(drop, screen_size)
          rect = anchor_rect
          columns = width.nil? ? rect.width : width
          columns = [columns.respond_to?(:call) ? columns.call : columns, screen_size.width].min
          if side == :below
            below(rect, drop.items.size, columns, screen_size)
          else
            beside(rect, drop.items.size, columns, screen_size)
          end
        end

        private

        # Beneath the anchor, flipped above when the rows won't fit below,
        # clamped — with the list scrolling — when neither side has room; the
        # left edges line up, sliding left only far enough to stay on screen.
        # @param anchor [Rect]
        # @param rows [Integer]
        # @param width [Integer]
        # @param screen_size [Size]
        # @return [Rect]
        def below(anchor, rows, width, screen_size)
          desired = [rows, max_rows].min
          beneath = anchor.top + anchor.height
          room_below = screen_size.height - beneath
          if desired <= room_below
            top = beneath
            height = desired
          elsif anchor.top >= room_below
            height = [desired, anchor.top].min
            top = anchor.top - height
          else
            height = room_below
            top = beneath
          end
          Rect.new([anchor.left, screen_size.width - width].min.clamp(0, nil), top, width, height)
        end

        # Against the anchor's right edge, flipped to its left when the right
        # has no room; the first row lines up with the anchor, sliding up only
        # far enough to stay on screen.
        # @param anchor [Rect]
        # @param rows [Integer]
        # @param width [Integer]
        # @param screen_size [Size]
        # @return [Rect]
        def beside(anchor, rows, width, screen_size)
          height = [rows, max_rows, screen_size.height].min
          right = anchor.left + anchor.width
          left = if right + width <= screen_size.width || (anchor.left - width).negative?
                   right
                 else
                   anchor.left - width
                 end
          left = left.clamp(0, [screen_size.width - width, 0].max)
          top = [anchor.top, screen_size.height - height].min.clamp(0, nil)
          Rect.new(left, top, width, height)
        end
      end

      def initialize
        @list = Menu.new
        @list.cursor = List::Cursor.new
        @list.show_cursor_when_inactive = true # highlight the selection though focus stays on the driver
        super(content: @list)
        self.bg_color = Theme.ref(:input_bg_color)
      end

      # @param items [Array] the items to show, one row each; see {List#items=}.
      #   An open dropdown resizes to the new count on the next settle.
      # @return [void]
      def items=(items)
        @list.items = items
        reposition
      end

      # @return [Array] the items currently shown.
      def items = @list.items

      # @param proc [Proc, Method] item -> row; see {List#renderer}.
      # @return [void]
      def renderer=(proc)
        @list.renderer = proc
      end

      # The wrapped list, exposed so a driver can register on {List#on_item_chosen}
      # (its commit) and {List#on_cursor_changed} (a cascading driver drops the
      # panels belonging to the row the highlight just left). A driver tunes it
      # but never supplies it (`D_has_content`).
      # @return [List]
      attr_reader :list

      # @param cursor [List::Cursor] the highlight; see {List#cursor=}.
      # @return [void]
      def cursor=(cursor)
        @list.cursor = cursor
      end

      # @return [List::Cursor] the list's cursor (the current highlight).
      def cursor = @list.cursor

      # Moves the highlight to the item at `index`, scrolling it into view; see
      # {List#select}. The positional counterpart of {#move}, for a driver that
      # picked a row by something other than a key — a mnemonic letter, say.
      # @param index [Integer]
      # @return [Boolean] whether the highlight moved there.
      def select(index) = @list.select(index)

      # Opens the dropdown against `anchor` — directly beneath it, flipped above
      # when its rows won't fit below, clamped (with the list scrolling) when
      # neither side has room — or moves it there if it is open already.
      # Horizontally the left edges line up, sliding left only far enough to
      # keep the panel on screen.
      #
      #   drop.anchor_to(self)                            # follows the field, its width
      #   drop.anchor_to(self, width: method(:menu_width))
      #
      # Vertical flips but horizontal slides because covering the driver would
      # hide what is being chosen, while sharing its columns is the point.
      #
      # **`anchor` is the region actually occupied, and may be taller than one
      # row** — "beneath" means the row *after* it, so a multi-row driver (a
      # {Component::TextArea} carrying an autocomplete menu) is cleared entirely
      # rather than overdrawn from its second row down. A component anchor is
      # read through its {Component#absolute_extent_rect}, so a widget that
      # paints one row but is *assigned* more height ({ComboBox}, {Select})
      # hangs the panel off its face.
      #
      # The height is the item count, capped at `max_rows`, and follows
      # {#items=}. Settles before it returns, so a driver can forward a key to
      # the list, or read {#cursor_row_rect}, in the same handler.
      #
      # @param anchor [Component, Rect] the driver, followed wherever it moves,
      #   or a fixed region in screen coordinates. Of any height; the dropdown
      #   never covers it.
      # @param width [Integer, #call, nil] the panel's width in columns, clamped
      #   to the screen, or something answering it; `nil` (the default) takes
      #   the anchor's, which lines both edges up with a field. A driver that
      #   measures its labels passes its own. A label wider than the screen
      #   clips — {List} has no horizontal scrolling.
      # @param max_rows [Integer] rows shown before the list scrolls.
      # @return [void]
      def anchor_to(anchor, width: nil, max_rows: MAX_VISIBLE_ROWS)
        anchor_with(Anchored.new(anchor:, side: :below, width:, max_rows:))
      end

      # Opens the dropdown *beside* `anchor` — the placement a cascading submenu
      # wants, where {#anchor_to} is the placement a field's dropdown wants —
      # or moves it there if it is open already.
      #
      #   sub.anchor_beside(parent.cursor_row_rect, width: measured)
      #
      # Horizontally it sits against `anchor`'s right edge, **flipping** to its
      # left when the right has no room (and clamping to the screen when neither
      # side does). Vertically it **slides**: the panel's first row lines up with
      # the anchored row, sliding up only far enough to keep the panel on screen.
      #
      # The two axes are the mirror image of {#anchor_to}'s, for the same reason:
      # never cover the thing being chosen from. A field's dropdown must not
      # cover the field, so it flips *vertically* and shares its columns; a
      # submenu must not cover its parent panel, so it flips *horizontally* and
      # shares its rows.
      #
      # @param anchor [Rect, Component] the row the submenu belongs to, in screen
      #   coordinates — typically the parent dropdown's {#cursor_row_rect}.
      # @param width [Integer, #call] the panel's width in columns, clamped to
      #   the screen. **Required, with no default:** the anchor's width is the
      #   *parent's* and would be meaningless here, so the caller measures (see
      #   `design/decisions.md` `D_select` on why the width policy stays with the
      #   driver).
      # @param max_rows [Integer] rows shown before the list scrolls.
      # @return [void]
      def anchor_beside(anchor, width:, max_rows: MAX_VISIBLE_ROWS)
        anchor_with(Anchored.new(anchor:, side: :beside, width:, max_rows:))
      end

      # The highlighted row's rect **on screen** — what a cascading submenu
      # anchors against, via {#anchor_beside}. Screen coordinates because the
      # submenu is a sibling overlay rather than a child (`D_relative_rect`).
      #
      # It lives here rather than in the driver because {ListDropdown} owns the
      # list's geometry: a driver computing `top + position - scroll_top_row`
      # itself would have to reach through to the private list.
      # @return [Rect, nil] one row spanning the panel's width, or `nil` when
      #   the cursor is off-content ({List::Cursor::None}, an empty list) or its
      #   row is scrolled out of the viewport.
      def cursor_row_rect
        return nil if @list.rect.empty?
        return nil unless @list.cursor.position.between?(0, @list.items.size - 1)

        row = @list.cursor.position - @list.scroll_top_row
        return nil unless row.between?(0, @list.rect.height - 1)

        Rect.new(0, 0, @list.rect.width, 1).at(@list.to_screen(Point.new(0, row)))
      end

      # Forwards a cursor-movement key to the list. The driver calls this from
      # its own key handler; a truthy return means "consumed — stop here", falsy
      # means "not mine — proceed with normal editing/dispatch". Only {MOVE_KEYS}
      # are claimed, and only while open.
      # @param key [String]
      # @return [Boolean] true iff the key was consumed.
      def move(key)
        return false unless open? && MOVE_KEYS.include?(key)

        @list.handle_key?(key)
        true
      end

      # Commits the highlighted row by firing {List#on_item_chosen}, exactly as
      # pressing Enter on the focused list would — the driver calls this from its
      # own Enter branch.
      # @return [Boolean] true iff a row was chosen (false when the cursor is
      #   off-content).
      def choose = @list.handle_key?(Keys::ENTER)

      protected

      # The list fills the panel (inherited), and the gutter is on exactly when
      # the rows outrun it — derived here rather than written by whichever
      # anchor method placed the panel, so it is right again after a plain
      # `items=` too.
      # @return [void]
      def relayout
        super
        @list.scrollbar_visibility = @list.items.size > rect.height ? :visible : :gone
      end

      private

      # Opens or moves the panel and settles the pass, because both anchor
      # methods promise a panel that *is* placed: a driver reads
      # {#cursor_row_rect} or forwards a key to the list in the same handler,
      # and both measure rects this just assigned.
      # @param placement [Anchored]
      # @return [void]
      def anchor_with(placement)
        open? ? self.placement = placement : self.open(placement)
        flush_layout
      end
    end
  end
end
