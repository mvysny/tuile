# frozen_string_literal: true

module Tuile
  class Component
    # A column of {FormItem}s. Hand it a field and a caption; it builds the item
    # and stacks it below the last one.
    #
    #   form = Component::FormLayout.new
    #   form.add(username, caption: "Username", required: true)
    #   form.add(notes,    caption: "Notes", rows: 5)
    #   form.add(logging)   # a Checkbox paints its own "[x] Enable logging"
    #   form.add(save)      # a Button, so no caption row at all
    #
    #   Username ∙            ← the caption row, with the required marker
    #   [______________]      ← `rows:` content rows, 1 by default
    #   Must not be blank     ← the message row, which is also the gap
    #   Notes
    #   [              ]
    #
    # **You hand it fields, it holds items.** {#add} wraps whatever you give it
    # and returns the {FormItem} it built, so the chrome is the item's from the
    # start — `add(field, caption:)` reads as though it set the *field*'s
    # caption, and does not (`D_caption_ownership`). Name that field again
    # wherever this class takes one — {#remove}, {#constrain}, {#field_for}'s
    # answer — and the item around it responds. Hide that item, never the field:
    # its caption and message go with it and the rows come back here.
    #
    # == Implementation details
    # **Every row count is the caller's.** Nothing here measures and nothing is
    # asked of a field: a captioned item is handed `1 + rows + 1` rows, a
    # captionless one `rows + 1`. The message row doubles as the gap, which is
    # why there is no `spacing` — and why `rows:` is a placement constraint in
    # this layout's per-child map, exactly as `Fixed[n]` is in a {Layout::Box},
    # rather than a property of the item. See `D_form_layout`.
    #
    # **Overflow clips, and there is no scrolling.** Items are laid from the top
    # edge; the one straddling the bottom takes the rows that are left — a
    # {FormItem} serves its content first — and everything past it gets an empty
    # rect rather than a stale one (`D_empty_ancestor`).
    #
    # **The caption is read at every pass and nothing announces a change to it**,
    # so one that appears or disappears after the item is placed resizes it at
    # the next `rect=` rather than at once. Pass it to {#add} and the question
    # never arises.
    class FormLayout < Layout
      # Placement for an item wired in through `add_child` instead of {#add}.
      # @return [Hash{Symbol => Object}]
      DEFAULT_PLACEMENT = { rows: 1 }.freeze

      def initialize
        super
        # Identity-keyed: two == items are still two distinct slots.
        @placements = {}.compare_by_identity
      end

      # Wraps `field` in a {FormItem}, adds it, and re-runs the layout.
      #
      #   item = form.add(notes, caption: "Notes", rows: 5)
      #   item.required = true   # the chrome is the item's, so tune it there
      #
      # @param field [Component] the field to wrap — or a ready-made {FormItem},
      #   which is adopted as it stands.
      # @param caption [String, StyledString, nil] the caption row's text. Omit
      #   it for a widget that paints its own face, such as a {Checkbox} or a
      #   {Button}, and the item reserves no caption row.
      # @param required [Boolean] paints {FormItem.required_marker} beside the
      #   caption.
      # @param rows [Integer] content rows for the field; `>= 1`.
      # @param at [Integer, nil] position among the existing items; appends when
      #   nil. The index is part of the contract — it is paint and Tab order.
      # @raise [TypeError] unless `field` is a {Component}.
      # @raise [ArgumentError] on a `rows` below 1, on `caption:` or `required:`
      #   passed alongside a ready-made item, or from {FormItem} when `required:`
      #   has no caption to sit beside.
      # @return [FormItem] the item, whether built here or handed in.
      def add(field, caption: nil, required: false, rows: 1, at: nil)
        validate_rows(rows)
        item = wrap(field, caption, required)
        add_child(item, at:)
        @placements[item] = { rows: }
        relayout
        item
      end

      # Re-sizes an item's content rows and re-runs the layout.
      #
      #   form.constrain(notes, 8)
      #
      # @param field [Component] the field, or the item around it.
      # @param rows [Integer] content rows; `>= 1`.
      # @raise [ArgumentError] when `field` is in no item of this form, or on a
      #   `rows` below 1.
      # @return [void]
      def constrain(field, rows)
        item = item_for(field)
        validate_rows(rows)
        return if placement(item)[:rows] == rows

        @placements[item] = { rows: }
        relayout
      end

      # Removes the item, forgets its placement, and closes the rows it left.
      #
      # The item keeps the field, so hand the *item* back to {#add} to put the
      # row back where it was — the {Layout::Box} idiom, with `rows:` on your
      # side because the placement is gone:
      #
      #   form.remove(notes)               # out, siblings move up
      #   form.add(item, rows: 5, at: 1)   # back where it was
      #
      # @param field [Component] the field, or the item around it.
      # @raise [ArgumentError] when `field` is in no item of this form.
      # @return [void]
      def remove(field)
        item = item_for(field)
        super(item)
        @placements.delete(item)
        relayout
      end

      # The field under a caption — sugar, since the association is a {FormItem}
      # in the tree and an ordinary walk answers the same question.
      #
      #   form.field_for(caption: "Username").text = "admin"
      #
      # @param caption [String, StyledString] matched against {FormItem#caption}
      #   as plain text; with duplicates, the first item wins.
      # @return [Component, nil] the wrapped field, or nil when no item matches
      #   or the matching one holds nothing.
      def field_for(caption:)
        wanted = caption.to_s
        children.find { _1.caption.to_s == wanted }&.content
      end

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        super
        relayout
      end

      protected

      # Re-divides the column: a hidden item gives up its content rows *and* the
      # fused gap row below them, and everything under it moves up.
      # @param _child [Component]
      # @return [void]
      def handle_child_visibility_changed(_child)
        super
        relayout
      end

      private

      # Stacks the items from the top edge, each {#item_height} tall, and clips
      # at the bottom.
      #
      # Deliberately *no* `return if rect.empty?` guard: that strands the items
      # at the coordinates they last had, and the next full repaint paints them
      # there (`D_empty_ancestor`).
      # @return [void]
      def relayout
        collapsed = Rect.new(rect.left, rect.top, 0, 0)
        top = rect.top
        bottom = rect.empty? ? top : top + rect.height
        children.each do |item|
          rows = item.visible? ? [item_height(item), bottom - top].min : 0
          item.rect = rows.positive? ? Rect.new(rect.left, top, rect.width, rows) : collapsed
          top += rows
        end
        invalidate
      end

      # @param item [FormItem]
      # @return [Integer] the rows it is handed: a caption row when it carries a
      #   caption, its content rows, and the message row that doubles as the gap.
      def item_height(item) = (item.caption.empty? ? 0 : 1) + placement(item)[:rows] + 1

      # @param item [FormItem]
      # @return [Hash{Symbol => Object}] the item's `rows`.
      def placement(item) = @placements[item] || DEFAULT_PLACEMENT

      # @param field [Component]
      # @param caption [String, StyledString, nil]
      # @param required [Boolean]
      # @raise [TypeError] unless `field` is a {Component}.
      # @raise [ArgumentError] when a ready-made item is handed chrome arguments.
      # @return [FormItem]
      def wrap(field, caption, required)
        raise TypeError, "expected Component, got #{field.inspect}" unless field.is_a?(Component)
        return FormItem.new(field, caption:, required:) unless field.is_a?(FormItem)

        unless caption.nil? && !required
          raise ArgumentError, "#{field} is already a FormItem: it carries its own caption and marker"
        end

        field
      end

      # @param field [Component] a field, or an item of this form.
      # @raise [ArgumentError] when neither.
      # @return [FormItem]
      def item_for(field)
        return field if children.any? { _1.equal?(field) }

        item = children.find { _1.content.equal?(field) }
        raise ArgumentError, "#{field} is in no item of #{self}" if item.nil?

        item
      end

      # @param rows [Integer]
      # @raise [ArgumentError] unless `rows` is a positive Integer.
      # @return [void]
      def validate_rows(rows)
        return if rows.is_a?(Integer) && rows.positive?

        raise ArgumentError, "rows expects a positive Integer, got #{rows.inspect} — " \
                             "hide an item with visible = false rather than starving it"
      end
    end
  end
end
