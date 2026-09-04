# frozen_string_literal: true

module Tuile
  class Component
    # Single-select from a set of typed items, one row each. Arrows move a
    # cursor; Space, Enter or a left click selects the row under it:
    #
    #    (*) Ascending
    #    ( ) Descending    <- cursor row, highlighted across the full width
    #    ( ) Unsorted
    #   ^ the composed {List}'s one-column gutter
    #
    #   rg = Component::RadioGroup.new(items: %w[Ascending Descending Unsorted])
    #   rg.value = "Descending"                      # or seed it via the ctor
    #   rg.on_value_change = ->(order) { resort(order) }
    #   rg.value                                     # => "Descending"
    #   rg.item_label = ->(o) { o.title }            # default :to_s
    #
    # {#value} is **the selected item itself** — of whatever type {#items}
    # holds, never its label. `nil` means nothing is selected: that is the
    # initial state, and assigning it is the only way back, since Space on the
    # already-selected row is a no-op rather than a deselect.
    #
    # Composes rather than subclasses, like {ComboBox}: a {List} of the items
    # is its single child, which is where the cursor, scrolling, the scrollbar
    # and per-row mouse hit-testing come from — the group only supplies the
    # {List#renderer} that puts the marker in front of the label. {#list} is
    # that list, exposed read-only so an app can tune it
    # (`scrollbar_visibility`, `show_cursor_when_inactive`, …) but never swap it
    # out. Rows beyond {#rect}'s height scroll; the inner list is the tab stop,
    # not the group.
    #
    # == The cursor is chrome
    # The cursor and the selection are two independent things, as in
    # {CheckboxGroup} — arrows roam without changing {#value}, so a listener
    # that resorts a pane fires once on intent instead of once per row crossed.
    # {#value=} therefore does *not* move the cursor. An app that wants it
    # parked on the selection parks it:
    #
    #   rg.list.cursor = List::Cursor.new(position: rg.items.index(rg.value))
    #
    # {#items=} is the one thing that moves it, clamping it back into range.
    #
    # == +items+ is chrome; +value+ is authoritative
    # {#items=} changes only what is *presented*. It never touches {#value} and
    # never fires {HasValue#on_value_change}, and a selected item absent from
    # {#items} renders no marked row while surviving intact — so a form saved
    # without the user editing anything changes nothing silently. Keeping the
    # two in sync is the app's job. Same contract as {ComboBox#value} and
    # {CheckboxGroup#value}.
    #
    # == Implementation details
    # Two `==`-equal items share one selection, so selecting either marks both
    # rows; two *distinct* items that merely render the same label stay
    # independent, because a row resolves to its own item, never to its label.
    #
    # Rows are `(*) `/`( ) ` literals, mirroring {Checkbox}'s convention rather
    # than importing constants from it. ASCII deliberately: `(•)` would measure
    # two columns in a terminal configured for East-Asian-Ambiguous glyphs and
    # shift every row's text, which no test would catch.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class RadioGroup < Component
      include HasValue

      # @param items [Array] the items to present, one row each; also settable
      #   via {#items=}.
      # @param value [Object, nil] the initially selected item. Seeds the
      #   backing ivar directly, so no listener fires and assignment order
      #   doesn't matter to a form helper.
      def initialize(items: [], value: nil)
        super()
        @item_label = :to_s.to_proc
        @value = value
        @on_value_change = nil

        list = List.new
        # A List has no cursor at all by default (Cursor::None, position -1).
        list.cursor = List::Cursor.new
        list.renderer = method(:render_row)
        list.on_item_chosen = ->(_index, item) { self.value = item }
        list.items = items.to_a
        @list = list
        add_child(list, at: 0)
      end

      # The composed {List}: an app may *tune* it — its scrollbar, its cursor,
      # `show_cursor_when_inactive` — but never replace it, since this group's
      # renderer and selection are wired into this one. Those knobs are {List}
      # concepts rather than group concepts, which is why they are reached here
      # instead of forwarded (`DECISIONS.md` `D_wrapping_field`).
      # @return [List]
      attr_reader :list

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        super
        list.rect = rect
      end

      # @return [void]
      def on_focus
        super
        # The list is what the arrows drive, so it takes the focus this group
        # was given; the group itself claims only Space.
        screen.focused = list if list.focusable?
      end

      # @return [Array] the presented items.
      def items = list.items

      # @return [Proc, Method] item -> row label (a `String`, {StyledString}, or
      #   anything with `#to_s`); `:to_s` by default.
      attr_reader :item_label

      # Replaces the presented rows, leaving {#value} untouched and clamping the
      # cursor back into range.
      # @param new_items [Array]
      # @raise [TypeError] unless `new_items` is an `Array`.
      # @return [void]
      def items=(new_items)
        raise TypeError, "expected Array, got #{new_items.inspect}" unless new_items.is_a?(Array)

        # Before the items land, so the single {List#on_cursor_changed} that
        # {List#items=} fires reports the final row rather than a stale one.
        clamp_cursor(new_items.size)
        list.items = new_items
      end

      # @param proc [Proc, Method] item -> row label.
      # @return [void]
      def item_label=(proc)
        @item_label = proc
        list.refresh_rows
      end

      # Selects `new_value`, firing {HasValue#on_value_change} when it really
      # changed. The cursor stays where it is.
      # @param new_value [Object, nil] `nil` selects nothing; an item outside
      #   {#items} is kept but renders no marked row.
      # @return [void]
      def value=(new_value)
        # HasValue#value= no-ops on an unchanged value; this guard is what also
        # skips the row rebuild.
        return if value == new_value

        super
        list.refresh_rows
      end

      # Selects the cursor row on Space. Nothing else is claimed: the composed
      # {List} — being the focused component — has already had its chance at the
      # key (its arrows, Home/End, PgUp/PgDn, ^U/^D and Enter), and whatever
      # neither of us wants bubbles on to an ancestor.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless key == " "

        select_at(list.cursor.position)
        true
      end

      private

      # Selects the item on row `index`; an index outside {#items} is ignored —
      # {List::Cursor::None}'s `-1` would otherwise select the *last* item.
      # @param index [Integer]
      # @return [void]
      def select_at(index)
        return unless index.between?(0, items.size - 1)

        self.value = items[index]
      end

      # @param item [Object]
      # @return [StyledString] the item's row: its label behind a selection
      #   marker. The {List} calls this at paint time, so the marker tracks
      #   {#value} without re-rendering anything but the visible rows.
      def render_row(item)
        StyledString.plain(item == value ? "(*) " : "( ) ") + label_for(item)
      end

      # Pulls an over-range cursor back onto the last row (row 0 when there are
      # none). {List#items=} leaves a stale cursor alone, which would strand it
      # off-content: no highlight, a dead Enter, and a Space that resolves to
      # `nil` and silently clears the selection.
      # @param item_count [Integer] size of the incoming item list.
      # @return [void]
      def clamp_cursor(item_count)
        cursor = list.cursor
        # go_to_last funnels through Cursor#go's clamp(0, nil), so an empty
        # items list floors at 0 instead of going negative.
        cursor.go_to_last(item_count) if cursor.position >= item_count
      end

      # @param item [Object]
      # @return [StyledString, String] whichever {StyledString#+} accepts on the
      #   right — so a styled label keeps its spans and a plain one is parsed.
      def label_for(item)
        label = @item_label.call(item)
        label.is_a?(StyledString) ? label : label.to_s
      end
    end
  end
end
