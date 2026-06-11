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
        # Optional bottom-row chrome that overlays the bottom border (e.g. a
        # search field).
        @footer = nil
        @footer_sizing = Sizing::FILL
        update_content_size
      end

      def focusable? = true

      # @return [Component, nil] optional component overlaying the bottom border
      #   row.
      attr_reader :footer

      # @return [Sizing] how the footer's width is computed from the window's
      #   inner width; defaults to {Sizing::FILL} (the footer spans the full
      #   inner width). The footer's height is always 1 (the border row).
      attr_reader :footer_sizing

      # Sets the footer width policy and re-lays-out the footer.
      # @param sizing [Sizing]
      def footer_sizing=(sizing)
        raise TypeError, "expected Sizing, got #{sizing.inspect}" unless sizing.is_a?(Sizing)
        return if @footer_sizing == sizing

        @footer_sizing = sizing
        layout_footer
        invalidate # repaint border cells the footer may have just vacated
      end

      # Sets the bottom-row chrome slot. The footer overlays the bottom border
      # row and is positioned automatically — its width is governed by
      # {#footer_sizing}; pass `nil` to remove.
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

      # Re-lays-out a {Sizing::WRAP_CONTENT} footer when the footer's natural
      # size changes, and folds a content resize into the window's own
      # natural size (whose change then bubbles to the window's parent — e.g.
      # a {Popup} re-self-sizes). The footer deliberately does *not*
      # participate in the window's {#content_size}: it is decoration
      # overlaying the border, and must not drive the window's size — if it
      # doesn't fit, it is clipped to the inner width.
      # @param child [Component]
      # @return [void]
      def on_child_content_size_changed(child)
        if child.equal?(@footer)
          old_rect = @footer.rect
          layout_footer
          # Repaint on any footer geometry change: a shrinking footer vacates
          # border cells that must be re-dashed (a growing one merely
          # overdraws, but distinguishing isn't worth the code).
          invalidate if @footer.rect != old_rect
        else
          update_content_size
        end
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

      # Paints the window border.
      # @return [void]
      def repaint_border
        return if rect.empty?

        frame = build_frame(frame_caption)
        frame = screen.theme.active_border(frame) if active?
        screen.print frame
      end

      # The caption text as it appears in the rendered border, including the
      # shortcut prefix when {#key_shortcut} is set.
      # @return [String]
      def frame_caption
        c = @caption || ""
        key_shortcut.nil? ? c : "[#{key_shortcut}]-#{c}"
      end

      # Builds the border as a single string with embedded cursor-positioning
      # escapes, mirroring the layout {TTY::Box.frame} used to produce. Title
      # is clipped to fit the inner width so the box never overflows {#rect}.
      # @param caption [String]
      # @return [String]
      def build_frame(caption)
        w = @rect.width
        h = @rect.height
        top = @rect.top
        left = @rect.left
        inner_w = [w - 2, 0].max

        title = caption.to_s
        title = title[0, inner_w] if title.length > inner_w
        dashes = "─" * (inner_w - title.length)

        out = +""
        out << TTY::Cursor.move_to(left, top) << "┌#{title}#{dashes}┐"
        (1..(h - 2)).each do |dy|
          out << TTY::Cursor.move_to(left, top + dy) << "│"
          out << TTY::Cursor.move_to(left + w - 1, top + dy) << "│"
        end
        out << TTY::Cursor.move_to(left, top + h - 1) << "└#{"─" * inner_w}┘" if h >= 2
        out
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

      # Positions the footer over the bottom border row, with its width
      # resolved by {#footer_sizing} against the inner width. A
      # {Sizing::WRAP_CONTENT} footer with zero natural width gets an empty
      # rect — i.e. it is invisible, as if never assigned.
      # @return [void]
      def layout_footer
        return if @footer.nil? || rect.empty?

        available = [rect.width - 2, 0].max
        width = @footer_sizing.resolve(available, @footer.content_size.width)
        @footer.rect = Rect.new(rect.left + 1, rect.top + rect.height - 1, width, 1)
      end
    end
  end
end
