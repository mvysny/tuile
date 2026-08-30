# frozen_string_literal: true

module Tuile
  class Component
    # A transient message in the screen's top-right corner — the TTY toast:
    #
    #   Component::Notification.show("Saved")
    #   Component::Notification.show("Disk full", color: Theme.ref(:error))
    #
    #   ┌─────────┐  ← flush: row 0, right edge at the last column
    #   │Saved    │  ← oldest on top, retires in 3 s
    #   │Disk full│  ← then this one, 3 s after that
    #   └─────────┘
    #
    # {show} is the only entry point ({new} is private): it finds the live
    # notification and appends to it, so a burst stacks as entries in one box
    # instead of opening five overlapping ones.
    #
    # One repeating ticker retires the **oldest** entry every {DISPLAY_SECONDS}
    # and closes the box when the last one goes — five messages raised together
    # appear at once and drain over fifteen seconds. A message arriving mid-cycle
    # waits its turn and does *not* restart the clock, so the bottom entry of a
    # full box is visible for about `N × DISPLAY_SECONDS`. Past {MAX_MESSAGES} a
    # message is dropped and reported to {Tuile.logger}; an app notifying faster
    # than that wants a {Component::LogWindow}.
    #
    # The box is flush to the corner, at most {WIDTH_FRACTION} of the screen wide
    # (floor {MIN_CAP_WIDTH}) and {HEIGHT_FRACTION} tall, and **grows but never
    # shrinks** while it lives; a long message wraps to {MAX_ROWS_PER_MESSAGE}
    # rows and is then ellipsized, and entries past the height cap wait unpainted.
    # `DECISIONS.md` `D_notification` has why each of those is what it is.
    #
    # Three things it deliberately doesn't do:
    #
    # - **Take focus, or receive keys.** An {Overlay} sits off the
    #   key-dispatch scope ({ScreenPane#handle_key}), so no key arrives here at
    #   all. A left click *on the box* dismisses ({#handle_mouse}); an app
    #   wanting a key registers a global shortcut and calls {Overlay#close}. A
    #   click *elsewhere* does not — this is the one overlay with
    #   {Overlay#close_on_outside_click?} false, since a toast is timed and an
    #   unrelated click is not about it.
    # - **Follow a theme flip.** A `Theme::Ref` `color:` is resolved once, when
    #   the message is added — a toast lives seconds, so there is no
    #   {Component#on_theme_changed} rebuild.
    # - **Take a size.** An {Overlay} has no declared box; the messages decide
    #   this one's, in {#reposition}.
    class Notification < Overlay
      # Most messages held at once, counting both the painted ones and any
      # waiting for room. Chosen from reading time rather than geometry: the
      # drain rate is one message per {DISPLAY_SECONDS}, so the queue length *is*
      # a duration, and 5 × 3 s is about the longest a corner box should own the
      # screen — and about as many short lines as anyone reads.
      # @return [Integer]
      MAX_MESSAGES = 5

      # Rows a single message may occupy before it is ellipsized.
      # @return [Integer]
      MAX_ROWS_PER_MESSAGE = 3

      # Seconds between retirements — how long the oldest message is held.
      # @return [Float]
      DISPLAY_SECONDS = 3.0

      # Fraction of the screen width the box may not exceed (see {MIN_CAP_WIDTH}).
      # @return [Float]
      WIDTH_FRACTION = 0.4

      # Fraction of the screen height the box may not exceed.
      # @return [Float]
      HEIGHT_FRACTION = 0.4

      # Floor under the width cap, so 40 % of an 80-column terminal doesn't
      # ellipsize every message down to five words.
      # @return [Integer]
      MIN_CAP_WIDTH = 34

      # Separator for re-joining wrapped rows before ellipsizing.
      # @return [StyledString]
      SPACE = StyledString.parse(" ")

      # Hard-line separator handed to {TextView#text=}.
      # @return [StyledString]
      ROW_BREAK = StyledString.parse("\n")
      private_constant :SPACE, :ROW_BREAK

      # Shows `text` in the corner, creating the box if none is open and
      # appending to it if one is.
      #
      # @param text [String, StyledString, nil] the message. A `String` is parsed
      #   via {StyledString.parse}, so embedded ANSI is honored. `nil` and the
      #   empty string are no-ops (nothing is shown, nothing is created).
      # @param color [Color, Theme::Ref, Symbol, Integer, Array<Integer>, nil]
      #   applied to every span of the message via {StyledString#with_fg}. A
      #   {Theme::Ref} is resolved against the current theme *now* — see the
      #   class docs on theme following. `nil` leaves the message's own colors
      #   alone.
      # @return [Notification, nil] the live notification, or `nil` when `text`
      #   was empty.
      # @raise [Tuile::Error] when the screen is closed, or when called from a
      #   thread that doesn't currently own the UI — a background job raising a
      #   notification must marshal it: `screen.event_queue.submit { ... }`.
      def self.show(text, color: nil)
        Screen.instance.check_locked
        return nil if StyledString.parse(text).empty?

        live = Screen.instance.pane.popups.find { _1.is_a?(Notification) }
        return live.tap { _1.add_message(text, color: color) } unless live.nil?

        # Message first, so the box is sized before it is mounted: opening an
        # empty 0×0 popup and then growing it would paint a frame of nothing.
        new.tap do |notification|
          notification.add_message(text, color: color)
          notification.open
        end
      end

      private_class_method :new

      def initialize
        # Built before `super`, because Overlay#initialize assigns the content
        # and our #reposition override reads every one of these.
        @messages = []
        @high_water = 0
        @ticker = nil
        @view = TextView.new
        @window = Window.new
        @window.content = @view
        super(content: @window, close_on_outside_click: false)
      end

      # Appends a message, dropping it (with a {Tuile.logger} warning) once
      # {MAX_MESSAGES} are held. Public so a caller holding the instance can
      # append without repeating {show}'s lookup.
      # @param text [String, StyledString, nil] see {show}. Empty is a no-op.
      # @param color [Color, Theme::Ref, Symbol, Integer, Array<Integer>, nil]
      #   see {show}.
      # @return [void]
      # @raise [Tuile::Error] see {show}.
      def add_message(text, color: nil)
        # Explicit rather than inherited-through-invalidate: this appends to
        # @messages before anything repaints, so a wrong-thread call has to fail
        # before the message is recorded, not after.
        screen.check_locked
        message = build_message(text, color)
        return if message.empty?

        if @messages.size >= MAX_MESSAGES
          Tuile.logger.warn("Notification: dropping #{message.to_s.inspect}, " \
                            "#{MAX_MESSAGES} messages already queued")
          return
        end

        @messages << message
        @high_water = [@high_water, natural_width(message)].max
        reposition
        sync_ticker
      end

      # Recomputes the box from its messages and re-anchors it to the screen's
      # top-right corner — so a SIGWINCH re-wraps and re-anchors, where
      # {Overlay#reposition} would have kept the stale left column of a *derived*
      # position (off-screen entirely if the terminal narrowed).
      #
      # Rebuilds the {TextView}'s text too, and every mutation routes through
      # here, because the four are one computation: the wrap width *is* the box
      # width, the height *is* the wrapped row count, the left edge *is* derived
      # from the width.
      # @return [void]
      def reposition
        if @messages.empty?
          self.rect = Rect.new(0, 0, 0, 0)
          return
        end

        width = box_width
        rows = @messages.flat_map { |message| wrap_message(message, width - 2) }
        height = [rows.size + 2, cap_height].min
        @view.text = join_rows(rows)
        self.rect = Rect.new([screen.size.width - width, 0].max, 0, width, height)
      end

      # A left click dismisses the whole box, every message with it. Other buttons
      # are consumed and inert — including the scroll wheel, which would otherwise
      # nuke the box on a stray spin.
      #
      # Deliberately *replaces* rather than augments: neither `super` nor
      # {HasContent#handle_mouse} may run, since both end at a
      # `screen.focused = …` inside this subtree (see {Overlay#focusable?}).
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        close if event.button == :left
      end

      # @return [void]
      def on_attached
        super
        sync_ticker
      end

      # @return [void]
      def on_detached
        super
        sync_ticker
      end

      private

      # Retires the oldest message, closing the box when it was the last. Runs on
      # the event-loop thread, from the ticker.
      # @return [void]
      def retire_oldest
        @messages.shift
        @messages.empty? ? close : reposition
        sync_ticker
      end

      # Syncs the retirement clock from the invariant "something to retire, and on
      # screen" — the sole writer of `@ticker`. Four sites change whether it is
      # wanted (append, a retirement that empties the queue, {#close}, detach),
      # which is the 2×2 a start-in-{#on_attached} / cancel-in-{#on_detached} pair
      # gets half wrong. The early return is also what keeps an append from
      # *restarting* the clock and extending the oldest message's life.
      # @return [void]
      def sync_ticker
        want = attached? && !@messages.empty?
        return if want == !@ticker.nil?

        if want
          @ticker = screen.event_queue.tick(DISPLAY_SECONDS) { retire_oldest }
        else
          @ticker.cancel
          @ticker = nil
        end
      end

      # @param text [String, StyledString, nil]
      # @param color [Color, Theme::Ref, Symbol, Integer, Array<Integer>, nil]
      # @return [StyledString]
      def build_message(text, color)
        message = StyledString.parse(text)
        return message if color.nil? || message.empty?

        message.with_fg(color.is_a?(Theme::Ref) ? color.resolve(screen.theme) : color)
      end

      # Columns the message would like, ignoring wrapping — the *widest* of its
      # hard lines, not the sum of its spans (which would add every line
      # together for a message carrying `\n`).
      # @param message [StyledString]
      # @return [Integer]
      def natural_width(message) = message.lines.map(&:display_width).max || 0

      # Grow-only: the high-water mark is kept in *desired* columns and the cap
      # is applied here, last. Storing the clamped value instead would let a
      # SIGWINCH that narrows the terminal ratchet the box permanently down to
      # the narrow cap, with nothing to restore it when the terminal widens.
      # @return [Integer]
      def box_width = [@high_water + 2, cap_width].min

      # @return [Integer]
      def cap_width
        [[(screen.size.width * WIDTH_FRACTION).to_i, MIN_CAP_WIDTH].max, screen.size.width].min
      end

      # @return [Integer] at least 3: two border rows plus one row of message.
      def cap_height
        [[(screen.size.height * HEIGHT_FRACTION).to_i, 3].max, screen.size.height].min
      end

      # Wraps one message to `width` columns, capped at {MAX_ROWS_PER_MESSAGE}
      # rows.
      #
      # The overflow is ellipsized from the *joined remainder*, not by
      # ellipsizing the last kept row: that row usually already fits `width`, so
      # {StyledString#ellipsize} would be a no-op and the message would be
      # truncated with no `…` to say so.
      # @param message [StyledString]
      # @param width [Integer]
      # @return [Array<StyledString>]
      def wrap_message(message, width)
        rows = message.wrap(width)
        return rows if rows.size <= MAX_ROWS_PER_MESSAGE

        kept = rows.take(MAX_ROWS_PER_MESSAGE - 1)
        rest = rows[(MAX_ROWS_PER_MESSAGE - 1)..].inject { |joined, row| joined + SPACE + row }
        kept + [rest.ellipsize(width)]
      end

      # Joins pre-wrapped rows into one {StyledString} with `\n` separators, so
      # {TextView} takes them as hard lines and its own wrap is a no-op over
      # them (each row already fits the width it will be painted at).
      # @param rows [Array<StyledString>]
      # @return [StyledString]
      def join_rows(rows)
        return StyledString::EMPTY if rows.empty?

        rows.inject { |joined, row| joined + ROW_BREAK + row }
      end
    end
  end
end
