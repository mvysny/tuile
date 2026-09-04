# frozen_string_literal: true

module Tuile
  class Component
    # A window with a frame, a {#caption} and a content {Component}. Doesn't
    # support overlapping with other windows: it paints its entire contents and
    # doesn't clip if there are other overlapping windows.
    #
    # The window's `content` is unset by default; assign one via {#content=}.
    #
    # Window is considered invisible if {#rect} is empty. The window won't
    # draw when invisible. (Repaint of detached windows is short-circuited
    # by {Component#invalidate}; subclasses don't need to re-check.)
    class Window < Component
      include Component::HasContent
      include Component::HasCaption

      # @param caption [String, StyledString, nil] the border title, coerced
      #   the same way {HasCaption#caption=} coerces it.
      def initialize(caption = nil)
        super()
        @border_right = 1
        self.caption = caption
        @content = nil
        # The bottom row holds either a widget or chrome text, never both; see
        # the precedence note on #footer=.
        @footer_slot = Slot.new
        add_child(@footer_slot) # appended: the footer paints over the border row
        @footer_text = StyledString::EMPTY
      end

      def focusable? = true

      # @return [Component, nil] optional focusable component occupying the
      #   bottom border row, always spanning the full inner width.
      def footer = @footer_slot.content

      # @return [StyledString] optional chrome embedded into the bottom border
      #   line, mirroring {#caption} on the top line. Empty by default; hidden
      #   whenever a {#footer} component is present.
      attr_reader :footer_text

      # Sets the bottom-border chrome. Accepts a `String` (parsed via
      # {StyledString.parse}), a {StyledString}, or `nil` (clears it). The text
      # embeds into the bottom border at its own width with the border's dashes
      # filling the remainder, clipped to the inner width — border decoration,
      # not a component (not focusable). Hidden whenever a {#footer} component
      # occupies the bottom row (see the precedence note on {#footer=}).
      # @param text [String, StyledString, nil]
      def footer_text=(text)
        new_text = StyledString.parse(text)
        return if @footer_text == new_text

        @footer_text = new_text
        invalidate # repaint the bottom border row
      end

      # Mounts a component in the bottom border row, spanning the full inner
      # width and positioned automatically; `nil` removes it.
      #
      # Precedence: a footer component present hides {#footer_text}; absent, the
      # text embeds into the bottom border. No window needs both at once.
      # @param new_footer [Component, nil]
      # @raise [TypeError] if `new_footer` is neither a {Component} nor nil.
      # @raise [ArgumentError] if `new_footer` already has a parent.
      # @return [void]
      def footer=(new_footer)
        @footer_slot.content = new_footer
        layout_footer
        invalidate # repaint border row that the footer covers/uncovers
      end

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        super
        layout_footer
      end

      # @param value [Boolean]
      # @return [void]
      def scrollbar=(value)
        unless content.respond_to?(:scrollbar_visibility=)
          raise Tuile::Error,
                "scrollbar= requires a content component that supports scrollbar_visibility=, got #{content.inspect}"
        end

        content.scrollbar_visibility = value ? :visible : :gone
        @border_right = value ? 0 : 1
        invalidate
        layout(content)
      end

      # Fully repaints the window: the border ring here, the interior through
      # the content and footer it re-invalidates.
      #
      # Deliberately *not* `super`: the default would blank the whole rect
      # first, because the content slot is inset by the border and so never
      # tiles — and every one of those blanked border cells is one this method
      # is about to repaint identically, which marks it dirty and makes
      # {Buffer#flush} re-emit it. That cost 925 bytes on every unchanged
      # repaint of an 80×25 window, paid on each focus change
      # (`D_component_contract`). The ring is this window's own paint and the
      # interior is the content's, so the only cell nobody covers is an
      # interior with no content in it — cleared here, exactly.
      # @return [void]
      def repaint
        return if rect.empty?

        clear_background(content_rect) if content.nil? && !content_rect.empty?
        invalidate_children
        repaint_border
      end

      protected

      # @param content [Component]
      # @return [void]
      def layout(content) = content.rect = content_rect

      # The interior the content fills: inside the border on three sides, and on
      # the fourth only while there is a right border — {#scrollbar=} drops it so
      # the content's own bar takes that column.
      # @return [Rect] may be {Rect#empty? empty}, for a window too small to have
      #   an inside.
      def content_rect
        Rect.new(rect.left + 1, rect.top + 1, rect.width - 1 - @border_right, rect.height - 2)
      end

      # Paints the window border via {Component#draw_text}/{Component#draw_char},
      # so the border cells inherit {Component#effective_bg_color} — a
      # {Component#bg_color} on the window tints border and content alike. Both
      # border rows are clipped by *display* width, so no caption overflows the
      # box; when the window is active the whole border — the caption's own
      # colors included — is drawn in {Theme#active_border_color}.
      # @return [void]
      def repaint_border
        return if rect.empty?

        w = rect.width
        h = rect.height
        top = rect.top
        left = rect.left
        inner_w = [w - 2, 0].max

        fg = active? ? screen.theme.active_border_color : nil
        bar = StyledString::Style.new(fg: fg)
        draw_text(left, top, top_border(inner_w, fg).slice(0, w))
        (1..(h - 2)).each do |dy|
          draw_char(left, top + dy, "│", bar)
          # Skipped once {#scrollbar=} has given that column to the content: the
          # bar would paint over the border anyway, and painting it first only
          # dirties the column into every frame's diff (`D_component_contract`).
          draw_char(left + w - 1, top + dy, "│", bar) if @border_right.positive?
        end
        draw_text(left, top + h - 1, bottom_border(inner_w, fg).slice(0, w)) if h >= 2
      end

      # Builds the top border row: corners, {#caption} embedded at its own
      # width, dashes filling the remainder. The caption keeps its own styling
      # unless `fg` is set — an active window's border claims it.
      # @param inner_w [Integer] the border's interior width.
      # @param fg [Color, nil] the active-border color, or nil when inactive.
      # @return [StyledString]
      def top_border(inner_w, fg)
        title = caption.slice(0, inner_w)
        title = title.with_fg(fg) if fg
        dashes = StyledString.styled("─" * (inner_w - title.display_width), fg: fg)
        StyledString.styled("┌", fg: fg) + title + dashes + StyledString.styled("┐", fg: fg)
      end

      # Builds the bottom border row. The corners take the border color; the
      # interior is plain dashes when a {#footer} component occupies the row
      # (it overpaints them) or when there's no chrome, otherwise it carries
      # {#footer_text} embedded at its own width — keeping the text's own
      # styling — with dashes filling the remainder up to the inner width.
      # @param inner_w [Integer] the border's interior width.
      # @param fg [Color, nil] the active-border color, or nil when inactive.
      # @return [StyledString]
      def bottom_border(inner_w, fg)
        interior =
          if footer || @footer_text.empty?
            StyledString.styled("─" * inner_w, fg: fg)
          else
            embedded = @footer_text.slice(0, inner_w)
            embedded + StyledString.styled("─" * (inner_w - embedded.display_width), fg: fg)
          end
        StyledString.styled("└", fg: fg) + interior + StyledString.styled("┘", fg: fg)
      end

      private

      # Positions the footer slot over the bottom border row, spanning the full
      # inner width (the only dimension a bottom-row widget needs — the window
      # already knows it).
      #
      # An unoccupied slot gets an *empty* rect, not the row — a {Slot} clears
      # whatever it is given, which would blank the border underneath.
      # @return [void]
      def layout_footer
        if footer.nil? || rect.empty?
          @footer_slot.rect = Rect.new(0, 0, 0, 0)
          return
        end

        width = [rect.width - 2, 0].max
        @footer_slot.rect = Rect.new(rect.left + 1, rect.top + rect.height - 1, width, 1)
      end
    end
  end
end
