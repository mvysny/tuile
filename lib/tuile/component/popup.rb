# frozen_string_literal: true

module Tuile
  class Component
    # A modal dialog: an {Component::Overlay} centered on the screen, which
    # grabs focus, scopes keys to its own subtree, blocks clicks beneath it, and
    # closes on ESC or `q` (unless {#close_on_key?} is false).
    #
    #   window = Component::Window.new("Help")
    #   window.content = Component::List.new.tap { _1.lines = lines }
    #   Component::Popup.new(content: window).open
    #
    # Bare content also works (a {Component::Label}, a {Component::List}…), in
    # which case the popup is borderless. For a floating layer that does *not*
    # take focus or capture input — an autocomplete list anchored to a field, a
    # toast — use {Component::Overlay} directly.
    #
    # Its box is set by {#declared_size}, resolved against the screen every
    # layout pass, so it tracks resize:
    #
    #   Popup.new(content: w)                                  # Fraction::HALF, the default
    #   Popup.new(content: w, declared_size: Size.new(50, 12)) # clamped to the screen
    #   Popup.new(content: w, declared_size: Popup::ShrinkToContent[Fraction::HALF])
    #   # half the screen wide, as tall as w.measure_rows(that width), at most half
    #
    # Only {ShrinkToContent} consults the content, and only for rows: the width
    # is always declared. Otherwise the content fills the box and handles its own
    # overflow by wrapping and scrolling, so use content that can — a
    # {Component::TextView} or {Component::TextArea} — for anything longer than
    # fits. A {Component::Label} only truncates.
    #
    # == Implementation details
    #
    # `q` and ESC close the popup — handled here, at the top of the popup's own
    # subtree, so the key only arrives after every component on the focus chain
    # declined it (see {ScreenPane#handle_key?}). That's why typing `q` into a
    # nested {Component::TextField} doesn't dismiss the popup: the field consumes
    # it first. A popup in front of work that cannot be stopped turns this off
    # with {#close_on_key?}.
    #
    # A left click *outside* the popup closes it too — see
    # {Overlay#close_on_outside_click?} for the exact contract and
    # {Overlay#on_close} for the notice a driver hears when it happens.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class Popup < Overlay
      # A {Popup#declared_size} that shrinks its {#box} to the content's height:
      # the width is the box's, the height whatever the content's
      # {Component#measure_rows} answers at that width, never more than the
      # box's:
      #
      #   Popup::ShrinkToContent[Fraction::HALF]     # half the screen at most
      #   Popup::ShrinkToContent[Size.new(60, 20)]   # 60 wide, 20 rows at most
      #
      # Content answering `nil` (no content height) takes the whole box. The
      # question is re-asked on every layout pass and nothing else: content
      # whose rows change while open calls {Popup#reposition}.
      #
      # @!attribute [r] box
      #   @return [Size, Fraction] the ceiling, resolved as {Popup#declared_size}
      #     resolves it.
      class ShrinkToContent < Data.define(:box)
        # @param box [Size, Fraction] see {#box}.
        # @raise [ArgumentError] unless `box` is a {Size} or a {Fraction}.
        def initialize(box:)
          unless box.is_a?(Size) || box.is_a?(Fraction)
            raise ArgumentError, "ShrinkToContent expects a Size or a Fraction, got #{box.inspect}"
          end

          super
        end
      end

      # @param content [Component, nil] initial content; can be set later via
      #   {#content=}. The content fills the popup's {#rect}.
      # @param declared_size [Size, Fraction, ShrinkToContent] the popup's box; see
      #   {#declared_size=}. Defaults to {Fraction::HALF}.
      # @param close_on_outside_click [Boolean] true (default) to dismiss on a
      #   left click that misses this popup. See
      #   {Overlay#close_on_outside_click?}.
      # @param close_on_key [Boolean] true (default) to dismiss on ESC and `q`.
      #   See {#close_on_key?}.
      def initialize(content: nil, declared_size: Fraction::HALF, close_on_outside_click: true, close_on_key: true)
        super(content: content, close_on_outside_click: close_on_outside_click)
        @_declared_size = declared_size
        @_close_on_key = close_on_key
      end

      # Whether ESC and `q` close this popup (default true). False makes the
      # popup refuse both — for one in front of work that cannot be stopped
      # once it starts, where a dismissal would read as a cancel while the work
      # goes on. Pair it with `close_on_outside_click: false`, which refuses the
      # other light dismissal; {#close} from code still works, and is how the
      # work's owner takes the popup down when it is done.
      #
      # A refused key is *swallowed*, not passed on: the popup is modal, so the
      # loop's unhandled-ESC/`q` quit (`D_quit_key`) does not fire beneath it
      # either. A popup that cannot be dismissed also keeps the app from
      # quitting by those keys.
      # @return [Boolean]
      def close_on_key? = @_close_on_key

      # @param value [Boolean] see {#close_on_key?}.
      # @return [void]
      def close_on_key=(value)
        @_close_on_key = value
      end

      # The box this popup asks for, *as set* — a {Fraction} comes back
      # unresolved. {#rect} is the resolved answer. Named apart from `size`
      # because a component's `size` is its `rect.size`, which this is not: it
      # is an input re-read on every layout pass, not a report of the current
      # geometry.
      # @return [Size, Fraction, ShrinkToContent] see {#declared_size=}.
      def declared_size = @_declared_size

      # @return [Boolean] true — a Popup scopes key dispatch, grabs focus on
      #   open, and blocks clicks on the content beneath it.
      def modal? = true

      # @return [Boolean] true — {ScreenPane#add_popup} focuses a popup on open,
      #   and focus repair falls back to it when its subtree has no tab stop.
      def focusable? = true

      # Sets the popup's box; an open popup takes it on the next settle.
      # Accepts a {Fraction} (resolved against the screen every layout pass, so
      # it tracks resize), an absolute {Size} (clamped to the screen), or either
      # one wrapped in {ShrinkToContent}. This is
      # **authoritative**, not a preference: the screen applies exactly what
      # you ask for (clamped), with no negotiation — a popup has no siblings to
      # compete with.
      # @param new_size [Size, Fraction, ShrinkToContent]
      # @return [void]
      def declared_size=(new_size)
        @_declared_size = new_size
        reposition
      end

      # {#declared_size} resolved against `screen_size`: a {Fraction} scaled, a
      # {Size} clamped, a {ShrinkToContent} box shrunk to the content's rows.
      # @param screen_size [Size]
      # @return [Size]
      def declared_size_in(screen_size)
        return box_in(@_declared_size, screen_size) unless @_declared_size.is_a?(ShrinkToContent)

        box = box_in(@_declared_size.box, screen_size)
        rows = content&.measure_rows(box.width)
        # Floored at one row, so a zero answer can't leave an invisible modal.
        rows.nil? ? box : Size.new(box.width, [[rows, 1].max, box.height].min)
      end

      # @return [Overlay::Centered] a popup opens centered.
      def default_placement = Centered[]

      # `q` and ESC close the popup, or are swallowed when {#close_on_key?} is
      # false. The popup sits on the focus chain of whatever it wraps, so the
      # key reaches here by bubbling up from the focused content after that
      # content declined to handle it.
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

      private

      # @param box [Size, Fraction]
      # @param screen_size [Size]
      # @return [Size]
      def box_in(box, screen_size) = box.is_a?(Fraction) ? box.resolve(screen_size) : box.clamp(screen_size)
    end
  end
end
