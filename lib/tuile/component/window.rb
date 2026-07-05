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

      # @param caption [String]
      def initialize(caption = "")
        super()
        @border_right = 1
        @caption = caption
        @content = nil
        # Optional bottom-row widget slot (e.g. a search field), spanning the
        # full inner width; and optional bottom-border chrome text embedded in
        # the border line (mutually exclusive — the component, when present,
        # occupies the row and hides the text).
        @footer = nil
        @footer_text = StyledString::EMPTY
        update_content_size
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
        invalidate # repaint the bottom border line
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
        old&.parent = nil
        @footer = new_footer
        unless new_footer.nil?
          new_footer.parent = self
          new_footer.invalidate
          layout_footer
        end
        invalidate # repaint border row that the footer covers/uncovers
        on_child_removed(old) unless old.nil?
      end

      # @return [Array<Component>]
      def children
        @footer.nil? ? super : super + [@footer]
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

      # @return [String] the current caption, empty by default.
      attr_reader :caption

      # Sets new caption and repaints the window.
      # @param new_caption [String]
      def caption=(new_caption)
        @caption = new_caption
        invalidate
        update_content_size
      end

      # Sets the new content. Also recomputes the window's natural size.
      # @param new_content [Component, nil]
      def content=(new_content)
        super
        update_content_size
      end

      # Folds a content resize into the window's own natural size (whose
      # change then bubbles to the window's parent — e.g. a {Popup}
      # re-self-sizes). A footer resize is ignored: the footer always spans
      # the full inner width regardless of its natural size, and deliberately
      # does *not* participate in the window's {#content_size} — it is
      # decoration overlaying the border and must not drive the window's size.
      # @param child [Component]
      # @return [void]
      def on_child_content_size_changed(child)
        update_content_size unless child.equal?(@footer)
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

      # @param key [String, nil]
      # @return [void]
      def key_shortcut=(key)
        super
        # The shortcut key is shown in the caption — repaint.
        invalidate
        update_content_size
      end

      protected

      # @param content [Component]
      # @return [void]
      def layout(content)
        content.rect = Rect.new(rect.left + 1, rect.top + 1, rect.width - 1 - @border_right, rect.height - 2)
      end

      # Paints the window border into the {Screen#buffer}. Title is clipped to
      # the inner width so the box never overflows {#rect}; when the window is
      # active the whole border is drawn in {Theme#active_border_color}.
      # @return [void]
      def repaint_border
        return if rect.empty?

        w = rect.width
        h = rect.height
        top = rect.top
        left = rect.left
        inner_w = [w - 2, 0].max
        title = frame_caption.to_s
        title = title[0, inner_w] if title.length > inner_w
        dashes = "─" * (inner_w - title.length)

        fg = active? ? screen.theme.active_border_color : nil
        bar = StyledString::Style.new(fg: fg)
        buf = screen.buffer
        buf.set_line(left, top, StyledString.styled("┌#{title}#{dashes}┐", fg: fg))
        (1..(h - 2)).each do |dy|
          buf.set_char(left, top + dy, "│", bar)
          buf.set_char(left + w - 1, top + dy, "│", bar)
        end
        buf.set_line(left, top + h - 1, bottom_border(inner_w, fg)) if h >= 2
      end

      # Builds the bottom border line. The corners take the border color; the
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

      # The caption text as it appears in the rendered border, including the
      # shortcut prefix when {#key_shortcut} is set.
      # @return [String]
      def frame_caption
        c = @caption || ""
        key_shortcut.nil? ? c : "[#{key_shortcut}]-#{c}"
      end

      private

      # Recomputes the window's natural size: content's natural size (or the
      # caption, whichever is wider) plus the 2-character border. The footer
      # is deliberately excluded — see {#on_child_content_size_changed}. A
      # window with no content or caption sizes to `Size.new(2, 2)` (bare
      # border).
      # @return [void]
      def update_content_size
        inner_w = [content&.content_size&.width || 0, frame_caption.length].max
        inner_h = content&.content_size&.height || 0
        self.content_size = Size.new(inner_w + 2, inner_h + 2)
      end

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
