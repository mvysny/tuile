# frozen_string_literal: true

module Tuile
  class Component
    # Multi-select from a set of typed items, one checkable row each. Arrows move
    # a cursor; Space, Enter or a left click toggles the row under it:
    #
    #    [x] Errors
    #    [ ] Warnings     <- cursor row, highlighted across the full width
    #    [x] Info
    #   ^ the composed {List}'s one-column gutter
    #
    #   cg = Component::CheckboxGroup.new(items: %w[Errors Warnings Info])
    #   cg.value = %w[Errors Info]                    # any Enumerable, stored as a Set
    #   cg.on_value_change = ->(set) { filter(set) }   # once per toggle
    #   cg.value                                       # => #<Set: {"Errors", "Info"}>
    #   cg.item_label = ->(level) { level.name }       # default :to_s
    #
    # {#value} is a **frozen `Set` of the selected items themselves** — of
    # whatever type {#items} holds, never their labels. Frozen so `cg.value <<
    # item` fails loudly rather than mutating the selection behind
    # {HasValue#on_value_change}'s back; assign a new set or an `Array` instead.
    # Treat it as *unordered*: it iterates in toggle order, so use
    # `cg.items & cg.value.to_a` when you need {#items} order.
    #
    # Composes rather than subclasses, like {ComboBox}: a {List} is its single
    # {HasContent} child, which is where the cursor, scrolling, the scrollbar and
    # per-row mouse hit-testing come from. `content` is that list, so an app can
    # tune it (`scrollbar_visibility`, `show_cursor_when_inactive`, …). Rows
    # beyond {#rect}'s height scroll; the inner list is the tab stop, not the
    # group.
    #
    # == +items+ is chrome; +value+ is authoritative
    # {#items=} changes only what is *presented*. It never touches {#value} and
    # never fires {HasValue#on_value_change}, and a selected item absent from
    # {#items} renders no checked row while surviving intact — so a form saved
    # without the user editing anything changes nothing silently. Keeping the two
    # in sync is the app's job: `cg.value &= cg.items.to_set` reconciles them.
    # Same contract as {ComboBox#value}, one item at a time.
    #
    # There is no select-all — neither a key nor a header row. An app that wants
    # one writes `cg.value = cg.items` behind its own affordance.
    #
    # == Implementation details
    # Items need stable `#hash`/`#eql?`, since the selection is a `Set`: an item
    # mutated after being selected becomes unfindable. Two `==`-equal items also
    # share one selection — their rows check and uncheck together — whereas two
    # *distinct* items that merely render the same label toggle independently,
    # because a row resolves to an item by index.
    #
    # Rows repeat {Checkbox}'s `[x] `/`[ ] ` glyph convention rather than
    # importing a constant from it.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class CheckboxGroup < Component
      include HasContent
      include HasValue

      EMPTY_SELECTION = Set.new.freeze
      private_constant :EMPTY_SELECTION

      # @param items [Array] the items to present, one row each; also settable
      #   via {#items=}.
      # @param value [Enumerable, nil] the initial selection. Seeds the backing
      #   ivar directly, so no listener fires and assignment order doesn't
      #   matter to a form helper.
      def initialize(items: [], value: nil)
        super()
        @items = items.to_a
        @item_label = :to_s.to_proc
        @value = coerce(value)
        @on_value_change = nil

        list = List.new
        # A List has no cursor at all by default (Cursor::None, position -1).
        list.cursor = List::Cursor.new
        list.on_item_chosen = ->(index, _line) { toggle_at(index) }
        self.content = list
        rebuild_rows
      end

      # @return [Array] the presented items.
      attr_reader :items

      # @return [Proc, Method] item -> row label (a `String`, {StyledString}, or
      #   anything with `#to_s`); `:to_s` by default.
      attr_reader :item_label

      # Replaces the presented rows, leaving {#value} untouched.
      # @param new_items [Array]
      # @raise [TypeError] unless `new_items` is an `Array`.
      # @return [void]
      def items=(new_items)
        raise TypeError, "expected Array, got #{new_items.inspect}" unless new_items.is_a?(Array)

        @items = new_items
        rebuild_rows
      end

      # @param proc [Proc, Method] item -> row label.
      # @return [void]
      def item_label=(proc)
        @item_label = proc
        rebuild_rows
      end

      # @return [Set] the frozen empty set — {HasValue#empty?} means nothing is
      #   selected.
      def empty_value = EMPTY_SELECTION

      # Replaces the selection, firing {HasValue#on_value_change} when it really
      # changed. Stores a frozen `Set` *copy*, so a set the caller goes on
      # mutating can't reach in.
      # @param new_value [Enumerable, nil] `nil` selects nothing.
      # @raise [TypeError] unless `new_value` is an `Enumerable` or `nil`.
      # @return [void]
      def value=(new_value)
        selected = coerce(new_value)
        # HasValue#value= no-ops on an unchanged value; this guard is what also
        # skips the row rebuild.
        return if value == selected

        super(selected)
        rebuild_rows
      end

      # Toggles the cursor row on Space. Nothing else is claimed: the composed
      # {List} — being the focused component — has already had its chance at the
      # key (its arrows, Home/End, PgUp/PgDn, ^U/^D and Enter), and whatever
      # neither of us wants bubbles on to an ancestor.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless key == " "

        toggle_at(content.cursor.position)
        true
      end

      protected

      # Places the composed list across the whole rect ({HasContent} hook).
      # @param list [Component]
      # @return [void]
      def layout(list) = (list.rect = rect)

      private

      # Flips membership of the item on row `index`; an index outside {#items} is
      # ignored.
      # @param index [Integer]
      # @return [void]
      def toggle_at(index)
        return unless index.between?(0, @items.size - 1)

        item = @items[index]
        self.value = value.include?(item) ? value - [item] : value + [item]
      end

      # Re-renders every row from the current items, labels and selection.
      # @return [void]
      def rebuild_rows
        content.lines = @items.map do |item|
          StyledString.plain(value.include?(item) ? "[x] " : "[ ] ") + label_for(item)
        end
      end

      # @param new_value [Enumerable, nil]
      # @return [Set] a frozen copy; `nil` becomes {#empty_value}.
      # @raise [TypeError] on anything else.
      def coerce(new_value)
        return empty_value if new_value.nil?
        raise TypeError, "expected Enumerable, got #{new_value.inspect}" unless new_value.is_a?(Enumerable)

        Set.new(new_value).freeze
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
