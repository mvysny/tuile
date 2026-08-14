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
        # Optional bottom-row widget slot (e.g. a search field), spanning the
        # full inner width; and optional bottom-border chrome text embedded in
        # the border row (mutually exclusive — the component, when present,
        # occupies the row and hides the text).
        @footer = nil
        @footer_text = StyledString::EMPTY
      end

      def focusable? = true

      # @return [Component, nil] optional focusable component occupying the
      #   bottom border row, always spanning the full inner width.
      attr_reader :footer

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

      # Sets the bottom-row widget slot. The footer occupies the bottom border
      # row, spanning the full inner width, and is positioned automatically;
      # pass `nil` to remove.
      #
      # Precedence: a footer component present hides {#footer_text}; absent, the
      # text embeds into the bottom border. No window needs both at once.
      #
      # Symmetric to {#content=}: validates the new component, swaps parent
      # pointers, invalidates the old/new components and the window border, and
      # repairs focus via {#on_child_removed} if the removed footer held it.
      # @param new_footer [Component, nil]
      def footer=(new_footer)
        unless new_footer.nil? || new_footer.is_a?(Component)
          raise TypeError, "expected Component or nil, got #{new_footer.inspect}"
        end
        return if @footer == new_footer
        if !new_footer.nil? && !new_footer.parent.nil?
          raise ArgumentError, "#{new_footer} already has a parent #{new_footer.parent}"
        end

        old = @footer
        # Same slot-swap order as HasContent#content=: notified last, so the
        # focus repair cascades into the new occupant rather than the old.
        detach_child(old) unless old.nil?
        @footer = new_footer
        unless new_footer.nil?
          add_child(new_footer) # appended: the footer paints over the border row
          new_footer.invalidate
          layout_footer
        end
        invalidate # repaint border row that the footer covers/uncovers
        on_child_removed(old) unless old.nil?
      end

      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        if @footer&.rect&.contains?(event.point)
          @footer.handle_mouse(event)
        else
          super
        end
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

      # Fully repaints the window: both frame and contents.
      #
      # Window deliberately paints over its entire rect (border around the
      # edge, content/footer over the interior), so we don't need the
      # {Component#repaint} default's auto-clear — but we do still want its
      # "re-invalidate children" effect, since the border overpaints
      # whatever the content/footer drew on the perimeter. Calling super
      # handles both: the auto-clear is harmless (we re-paint over it), and
      # the invalidation queues content + footer for repaint in the same
      # cycle.
      # @return [void]
      def repaint
        return if rect.empty?

        super
        repaint_border
      end

      protected

      # @param content [Component]
      # @return [void]
      def layout(content)
        content.rect = Rect.new(rect.left + 1, rect.top + 1, rect.width - 1 - @border_right, rect.height - 2)
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
          draw_char(left + w - 1, top + dy, "│", bar)
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
          if @footer || @footer_text.empty?
            StyledString.styled("─" * inner_w, fg: fg)
          else
            embedded = @footer_text.slice(0, inner_w)
            embedded + StyledString.styled("─" * (inner_w - embedded.display_width), fg: fg)
          end
        StyledString.styled("└", fg: fg) + interior + StyledString.styled("┘", fg: fg)
      end

      private

      # Positions the footer over the bottom border row, spanning the full
      # inner width (the only dimension a bottom-row widget needs — the window
      # already knows it).
      # @return [void]
      def layout_footer
        return if @footer.nil? || rect.empty?

        width = [rect.width - 2, 0].max
        @footer.rect = Rect.new(rect.left + 1, rect.top + rect.height - 1, width, 1)
      end
    end
  end
end
