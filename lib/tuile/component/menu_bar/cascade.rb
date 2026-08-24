# frozen_string_literal: true

module Tuile
  class Component
    class MenuBar
      # The stack of open menu panels — one {ListDropdown} per level, the last
      # deepest — and the drill/pop/activate logic driving them. Private
      # machinery of {MenuBar}; an app never names it.
      #
      #   cascade.open_below(segment_rect, item)   # Enter/Down on the strip
      #   return true if cascade.handle_key(key)   # MenuBar#handle_key, first
      #   cascade.close                            # focus lost, or rect changed
      #
      # A panel is a **non-modal overlay, not a child**, so it never takes focus:
      # focus stays on the {MenuBar} for the whole interaction and every key
      # arrives via {MenuBar#handle_key}, which offers it here first. That is
      # {Component::Select}'s architecture extended to N levels, and it is why
      # nothing in the key-dispatch ladder changes.
      #
      # Widths are measured here, per level — the panel is as wide as the level's
      # widest label — because {ListDropdown} deliberately measures nothing
      # itself (`DECISIONS.md` `D-select`).
      #
      # == Implementation details
      # While open it consumes **everything** except the two keys that mean
      # "leave this menu sideways", which only the strip can answer: LEFT at
      # depth 1, and RIGHT on a row with no submenu. An open menu is quasi-modal
      # — firing an app's `s`-to-save behind a visible panel is worse than a dead
      # keystroke.
      #
      # UI-thread-confined, like everything in the tree (see {Screen}).
      class Cascade
        # The affordance painted on a row that opens a submenu. U+25B8 rather
        # than the obvious `▶`: like {Component::Select}'s `▾` it is East-Asian
        # **Neutral**, so it measures one column even under ambiguous-as-wide and
        # stays outside `D-ambiguous-width`'s bet, where `▶` and `▼` are
        # Ambiguous and would need an ASCII opt-in.
        # @return [String]
        SUBMENU_ARROW = "▸"

        # Columns a submenu arrow occupies, the space before it included.
        # @return [Integer]
        ARROW_WIDTH = 2

        def initialize
          @levels = []
        end

        # @return [Boolean] whether any panel is open.
        def open? = !@levels.empty?

        # @return [Integer] how many panels are open; `0` when closed.
        def depth = @levels.size

        # Opens `item`'s children directly beneath `anchor`, closing anything
        # already open first.
        # @param anchor [Rect] the strip segment the menu drops from.
        # @param item [Item] a childless one opens nothing.
        # @return [void]
        def open_below(anchor, item)
          close
          return unless item.submenu?

          push(item) { |drop, rows, width| drop.anchor_to(anchor, rows: rows, width: width) }
        end

        # Closes every open panel, deepest first.
        # @return [void]
        def close = truncate(0)

        # Offers a key to the deepest panel and to the cascade's own verbs.
        # @param key [String]
        # @return [Boolean] `true` when consumed — almost always, while open.
        #   `false` when closed, and for the two sideways keys {MenuBar} answers
        #   (see the class docs).
        def handle_key(key)
          return false unless open?
          return true if deepest.move(key)

          case key
          when Keys::ENTER, " " then activate_highlighted
          when Keys::RIGHT_ARROW
            return false unless highlighted(depth - 1)&.submenu?

            activate_highlighted
          when Keys::LEFT_ARROW
            return false if depth < 2

            pop
          when Keys::ESC then pop
          else
            # Only a printable: an open menu also swallows HOME, function keys
            # and the five-byte junk Keys.getkey returns for an unrecognized
            # escape sequence, and ringing at terminal noise is worse than
            # silence. A printable is a deliberate, visible act.
            Screen.instance.beep if Keys.printable?(key)
          end
          true
        end

        # Activates the deepest level's item bound to `key` — the drill-or-fire
        # the mnemonic shares with Enter. The highlight moves there *first*, so a
        # submenu anchors beside the row that opened it rather than beside
        # wherever the cursor happened to be.
        # @param key [String] a single printable, already downcased.
        # @return [Boolean] whether an item on the deepest level claimed it. A
        #   miss is never offered to a shallower level.
        def handle_mnemonic(key)
          return false unless open?

          level = depth - 1
          item, drop = @levels[level]
          index = item.items.index { |child| child.mnemonic == key }
          return false if index.nil?

          drop.select(index)
          activate(level, item.items[index])
          true
        end

        private

        # @return [ListDropdown] the deepest open panel.
        def deepest = @levels.last[1]

        # @return [void]
        def activate_highlighted = activate(depth - 1, highlighted(depth - 1))

        # Drills into `item`, or fires it and closes the cascade.
        #
        # @param level [Integer] the panel the item belongs to.
        # @param item [Item, nil] `nil` (an off-content cursor) does nothing.
        # @return [void]
        def activate(level, item)
          # Truncate first, for the mouse: a click on a shallower panel that is
          # still visible routes to *that* panel, so anything deeper is stale.
          truncate(level + 1)
          return if item.nil?

          if item.submenu?
            push_beside(level, item)
          else
            # Closed before the listener runs, so an action that opens a dialog
            # doesn't paint it under a menu. A listener-less leaf still closes:
            # activation stays uniform.
            close
            item.on_click&.call
          end
        end

        # Opens `item`'s children beside the row highlighted in `level`.
        # @param level [Integer]
        # @param item [Item]
        # @return [void]
        def push_beside(level, item)
          anchor = @levels[level][1].cursor_row_rect
          return if anchor.nil?

          push(item) { |drop, rows, width| drop.anchor_beside(anchor, rows: rows, width: width) }
        end

        # Mounts a panel for `item`'s children and yields it for geometry.
        # @param item [Item]
        # @yieldparam drop [ListDropdown]
        # @yieldparam rows [Integer]
        # @yieldparam width [Integer]
        # @return [void]
        def push(item)
          children = item.items
          drop = ListDropdown.new
          drop.renderer = renderer_for(children)
          drop.items = children
          drop.cursor = List::Cursor.new
          level = @levels.size
          # Wired *after* the items and cursor: {List#items=} and {List#cursor=}
          # both fire on_cursor_changed, so wiring first would have the fresh
          # panel truncate itself away as it was built.
          drop.on_item_chosen = ->(_index, child) { activate(level, child) }
          drop.on_cursor_changed = ->(_index, _child) { truncate(level + 1) }
          @levels << [item, drop]
          drop.open
          yield(drop, children.size, width_for(children))
        end

        # Closes the deepest panel; at depth 1 that closes the cascade.
        # @return [void]
        def pop = truncate(depth - 1)

        # @param count [Integer] how many panels to keep.
        # @return [void]
        def truncate(count)
          while depth > count
            _item, drop = @levels.pop
            drop.close
          end
        end

        # @param level [Integer]
        # @return [Item, nil] the item under `level`'s cursor; `nil` when it sits
        #   off-content. The range guard matters: a cursor at `-1` would
        #   otherwise index the *last* child.
        def highlighted(level)
          item, drop = @levels[level]
          position = drop.cursor.position
          position.between?(0, item.items.size - 1) ? item.items[position] : nil
        end

        # @param items [Array<Item>]
        # @return [Proc] item -> row: the label padded to the level's widest, plus
        #   an arrow column when any sibling has a submenu — so every arrow lands
        #   in the same column without asking the {List} how wide it ended up.
        def renderer_for(items)
          label_width = label_width_of(items)
          arrows = items.any?(&:submenu?)
          lambda do |item|
            row = item.cued_caption.ellipsize(label_width)
            row += StyledString.plain(" " * (label_width - row.display_width))
            next row unless arrows

            row + StyledString.plain(item.submenu? ? " #{SUBMENU_ARROW}" : " " * ARROW_WIDTH)
          end
        end

        # @param items [Array<Item>]
        # @return [Integer] the panel width: the rendered row plus {List}'s two
        #   row gutters, plus a scrollbar column when the rows can't all be shown.
        #   As in {Component::Select}, the scrollbar is predicted from the item
        #   count rather than the final height — a panel the screen clamps
        #   shorter than {ListDropdown::MAX_VISIBLE_ROWS} scrolls without having
        #   bought that column, and ellipsizes one character early.
        def width_for(items)
          row = label_width_of(items) + (items.any?(&:submenu?) ? ARROW_WIDTH : 0)
          row + 2 + (items.size > ListDropdown::MAX_VISIBLE_ROWS ? 1 : 0)
        end

        # @param items [Array<Item>]
        # @return [Integer]
        def label_width_of(items) = items.map { _1.cued_caption.display_width }.max || 0
      end
    end
  end
end
