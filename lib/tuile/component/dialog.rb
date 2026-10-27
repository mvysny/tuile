# frozen_string_literal: true

module Tuile
  class Component
    # A modal dialog: a bordered, captioned {Component::Overlay} centered on the
    # screen, which grabs focus, scopes keys to its own subtree, blocks clicks
    # beneath it, and closes on ESC or `q` (unless {#close_on_key?} is false).
    #
    #   list = Component::List.new.tap { _1.lines = lines }
    #   Component::Dialog.new("Help", content: list, footer_text: "q to close").open
    #
    #   ┌Help──────────────┐
    #   │first line        │
    #   └q to close────────┘   ← footer_text, optional
    #
    # A dialog that is a kind of its own — its keys, its buttons, its result —
    # subclasses it, passes its chrome up, and sets its content last:
    #
    #   class CpuFlagsDialog < Component::Dialog
    #     def initialize(flags)
    #       super("CPU flags", declared_size: Fraction.new(0.7, 0.7))
    #       @flags = flags
    #       self.content = Component::TextView.new.tap { _1.text = @flags.join(" ") }
    #     end
    #   end
    #
    # `content:` is for the anonymous one-liner above: passed up from a
    # subclass, it forces the widgets to be built before `super`, ahead of the
    # ivars they read.
    #
    # For a floating layer that does *not* take focus or capture input — an
    # autocomplete list anchored to a field, a toast — use {Component::Overlay}
    # directly.
    #
    # The dialog does *not* size itself to its content. Its box is set by
    # {#declared_size} — a {Fraction} (resolved against the screen every layout
    # pass, so it tracks resize) or an absolute {Size} (clamped to the screen).
    # The default is {Fraction::HALF}: half the screen, centered. The content
    # fills the inside of the border and handles its own overflow by wrapping and
    # scrolling, so use content that can — a {Component::TextView} or
    # {Component::TextArea} — for anything longer than fits. A
    # {Component::Label} only truncates.
    #
    # The border is lit in {Theme#active_border_color} while focus is inside the
    # dialog, so it dims while another dialog is stacked on top.
    #
    # == Implementation details
    #
    # `q` and ESC close the dialog — handled here, at the top of the dialog's own
    # subtree, so the key only arrives after every component on the focus chain
    # declined it (see {ScreenPane#handle_key?}). That's why typing `q` into a
    # nested {Component::TextField} doesn't dismiss the dialog: the field consumes
    # it first. A subclass handling keys of its own calls `super` for the ones it
    # declines. A dialog in front of work that cannot be stopped turns this off
    # with {#close_on_key?}.
    #
    # A left click *outside* the dialog closes it too — see
    # {Overlay#close_on_outside_click?} for the exact contract and
    # {Overlay#on_close} for the notice a driver hears when it happens.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class Dialog < Overlay
      include Component::HasCaption

      # @param caption [String, StyledString, nil] the border title, coerced the
      #   same way {HasCaption#caption=} coerces it.
      # @param content [Component, nil] initial content; can be set later via
      #   {#content=}. It fills the inside of the border; it does not determine
      #   the dialog's size.
      # @param declared_size [Size, Fraction] the dialog's box, border included,
      #   applied top-down. A {Fraction} is resolved against the screen each
      #   layout pass; a {Size} is clamped to the screen. Defaults to
      #   {Fraction::HALF}.
      # @param footer_text [String, StyledString, nil] see {#footer_text=}.
      # @param close_on_outside_click [Boolean] true (default) to dismiss on a
      #   left click that misses this dialog. See
      #   {Overlay#close_on_outside_click?}.
      # @param close_on_key [Boolean] true (default) to dismiss on ESC and `q`.
      #   See {#close_on_key?}.
      def initialize(caption = nil, content: nil, declared_size: Fraction::HALF, footer_text: nil,
                     close_on_outside_click: true, close_on_key: true)
        @_border_drawer = BorderDrawerInt.new
        super(content: content, close_on_outside_click: close_on_outside_click)
        @_declared_size = declared_size
        @_close_on_key = close_on_key
        self.caption = caption
        self.footer_text = footer_text
      end

      # Whether ESC and `q` close this dialog (default true). False makes the
      # dialog refuse both — for one in front of work that cannot be stopped
      # once it starts, where a dismissal would read as a cancel while the work
      # goes on. Pair it with `close_on_outside_click: false`, which refuses the
      # other light dismissal; {#close} from code still works, and is how the
      # work's owner takes the dialog down when it is done.
      #
      # A refused key is *swallowed*, not passed on: the dialog is modal, so the
      # loop's unhandled-ESC/`q` quit (`D_quit_key`) does not fire beneath it
      # either. A dialog that cannot be dismissed also keeps the app from
      # quitting by those keys.
      # @return [Boolean]
      def close_on_key? = @_close_on_key

      # @param value [Boolean] see {#close_on_key?}.
      # @return [void]
      def close_on_key=(value)
        @_close_on_key = value
      end

      # @return [StyledString] optional chrome embedded into the bottom border
      #   line, mirroring {#caption} on the top line. Empty by default.
      def footer_text = @_border_drawer.footer_text

      # Sets the bottom-border chrome — key hints, typically. Accepts a `String`
      # (parsed via {StyledString.parse}), a {StyledString}, or `nil` (clears
      # it). The text embeds into the bottom border at its own width with the
      # border's dashes filling the remainder, clipped to the inner width —
      # border decoration, not a component (not focusable).
      # @param text [String, StyledString, nil]
      # @return [void]
      def footer_text=(text)
        new_text = StyledString.parse(text)
        return if footer_text == new_text

        @_border_drawer.footer_text = new_text
        invalidate # repaint the bottom border row
      end

      # Hands the right border column to the content's scrollbar, or takes it
      # back.
      # @param value [Boolean]
      # @raise [Tuile::Error] unless the content supports `scrollbar_visibility=`.
      # @return [void]
      def scrollbar=(value)
        unless content.respond_to?(:scrollbar_visibility=)
          raise Tuile::Error,
                "scrollbar= requires a content component that supports scrollbar_visibility=, got #{content.inspect}"
        end

        content.scrollbar_visibility = value ? :visible : :gone
        @_border_drawer.right_border = !value
        invalidate
        invalidate_layout
      end

      # The box this dialog asks for, *as set* — a {Fraction} comes back
      # unresolved. {#rect} is the resolved answer. Named apart from `size`
      # because a component's `size` is its `rect.size`, which this is not: it
      # is an input re-read on every layout pass, not a report of the current
      # geometry.
      # @return [Size, Fraction] see {#declared_size=}.
      def declared_size = @_declared_size

      # @return [Boolean] true — a Dialog scopes key dispatch, grabs focus on
      #   open, and blocks clicks on the content beneath it.
      def modal? = true

      # @return [Boolean] true — {ScreenPane#add_overlay} focuses a dialog on open,
      #   and focus repair falls back to it when its subtree has no tab stop.
      def focusable? = true

      # Sets the dialog's box, border included; an open dialog takes it on the
      # next settle. Accepts a {Fraction} (resolved against the screen every
      # layout pass, so it tracks resize) or an absolute {Size} (clamped to the
      # screen). This is **authoritative**, not a preference: the screen applies
      # exactly what you ask for (clamped), with no negotiation — a dialog has
      # no siblings to compete with.
      # @param new_size [Size, Fraction]
      # @return [void]
      def declared_size=(new_size)
        @_declared_size = new_size
        reposition
      end

      # {#declared_size} resolved against `screen_size`: a {Fraction} scaled, a
      # {Size} clamped.
      # @param screen_size [Size]
      # @return [Size]
      def declared_size_in(screen_size)
        @_declared_size.is_a?(Fraction) ? @_declared_size.resolve(screen_size) : @_declared_size.clamp(screen_size)
      end

      # @return [Overlay::Centered] a dialog opens centered.
      def default_placement = Centered[]

      # `q` and ESC close the dialog, or are swallowed when {#close_on_key?} is
      # false. The dialog sits on the focus chain of its content, so the key
      # reaches here by bubbling up from the focused content after that content
      # declined to handle it.
      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_key?(key)
        if [Keys::ESC, "q"].include?(key)
          close if close_on_key?
          true
        else
          false
        end
      end

      # Fully repaints the dialog: the border ring here, the interior through
      # the content it re-invalidates.
      #
      # Deliberately *not* `super`: the default would blank the whole rect
      # first, because the content is inset by the border and so never tiles —
      # and every one of those blanked border cells is one this method is about
      # to repaint identically, which marks it dirty and makes {Buffer#flush}
      # re-emit it (`D_component_contract`). The only cell nobody covers is an
      # interior with no content in it — cleared here, exactly.
      # @param canvas [Canvas] see {Component#repaint}.
      # @return [void]
      def repaint(canvas)
        return if rect.empty?

        inner = content_rect
        canvas.fill(inner) if content.nil? && !inner.empty?
        invalidate_children
        fg = active? ? screen.theme.active_border_color : nil
        @_border_drawer.paint(canvas, rect.size, caption:, fg:)
      end

      protected

      # @return [void]
      def relayout
        content&.rect = content_rect
      end

      # The interior the content fills, inside the border. One rect for both
      # passes: what {#relayout} assigns the content, and what {#repaint} blanks
      # when there is no content to cover it.
      # @return [Rect]
      def content_rect = @_border_drawer.content_rect(rect.size)
    end
  end
end
