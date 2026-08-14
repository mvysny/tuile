# frozen_string_literal: true

module Tuile
  class Component
    # A one-row progress bar: a run of `█` growing left to right across {#rect},
    # over a `░` track.
    #
    #   ████████░░░░░░░░░░░░
    #
    #   bar   = Component::ProgressBar.new(range: 0..files.size)
    #   label = Component::Label.new
    #   add(bar)
    #   add(label)
    #
    #   def rect=(new_rect)             # the enclosing Layout positions both
    #     super
    #     bar.rect   = Rect.new(rect.left, rect.top, rect.width, 1)
    #     label.rect = Rect.new(rect.left, rect.top + 1, rect.width, 1)
    #   end
    #
    #   bar.value  = done
    #   label.text = "#{bar.percent}% — #{done}/#{files.size}"
    #
    # The bar paints no text of its own: put a {Label} beside it and feed it
    # {#percent} or {#fraction}, so the app words it ("42% — 3/7 files") and
    # places it freely. Display-only — not focusable, no keys, no mouse.
    #
    # While the total is still unknown, {#indeterminate=} swaps the fill for a
    # block sliding across the bar:
    #
    #   ░░░░░░░████░░░░░░░░░
    #
    # Both endpoints are exact: the bar is full only at {#max} and empty only at
    # {#min}, so a full bar always means done. Assign a one-row {#rect}; a taller
    # one paints the bar on its first row and leaves the rest to the background.
    #
    # == Implementation details
    # The `█`/`░` pair is the same one {VerticalScrollBar} uses — East-Asian
    # Ambiguous and Neutral respectively, so under an ambiguous-as-wide terminal
    # the rendered length would vary with the fill level. Shipped anyway, per
    # `DECISIONS.md` `D-ambiguous-width`: a bar that rhymes with the scrollbar
    # beats a third convention, and if that bet is ever reversed both swap
    # together.
    class ProgressBar < Component
      # Range covering the whole bar when none is given.
      # @return [Range]
      DEFAULT_RANGE = (0.0..1.0)

      # Frames per second of the indeterminate animation. The block advances one
      # cell per frame, so this is also its speed in cells/second.
      # @return [Integer]
      INDETERMINATE_FPS = 5

      # The indeterminate block is this fraction of the bar, at least one cell.
      # @return [Integer]
      BLOCK_DIVISOR = 5

      # @param range [Range] initial {#range=}.
      # @param value [Numeric, nil] initial {#value=}; `nil` starts at the range's
      #   lower bound.
      # @param indeterminate [Boolean] initial {#indeterminate=}.
      def initialize(range: DEFAULT_RANGE, value: nil, indeterminate: false)
        super()
        @value = 0.0
        @min = 0.0
        @max = 1.0
        @phase = 0
        @ticker = nil
        @indeterminate = false
        @bar_color = nil
        self.range = range
        self.value = value unless value.nil?
        self.indeterminate = indeterminate
      end

      # @return [Float] lower bound of {#range}.
      attr_reader :min

      # @return [Float] upper bound of {#range}.
      attr_reader :max

      # @return [Color, nil] the value as set, so a {Theme::Ref} comes back
      #   unresolved. Both glyphs paint in it; `nil` (the default) is the
      #   terminal's default foreground.
      attr_reader :bar_color

      # @return [Range] the scale {#value} is measured against.
      def range = @min..@max

      # Replaces the scale, re-clamping {#value} into it. `min == max` is legal
      # and reads as complete — a zero-length job has nothing outstanding — so
      # `bar.range = 0..files.size` needs no special case for an empty list.
      #
      # @param new_range [Range] inclusive; endpoints Numeric and finite.
      # @return [void]
      # @raise [ArgumentError] on an exclusive, inverted or non-finite range, or
      #   an endpoint `Float()` cannot parse.
      # @raise [TypeError] on a beginless or endless range — its `nil` endpoint
      #   is what `Float()` refuses — or any other type it refuses outright.
      def range=(new_range)
        raise ArgumentError, "range must be inclusive, got #{new_range.inspect}" if new_range.exclude_end?

        min = Float(new_range.begin)
        max = Float(new_range.end)
        raise ArgumentError, "range end #{max} is below its start #{min}" if max < min

        unless min.finite? && max.finite?
          raise ArgumentError, "range endpoints must be finite (use indeterminate = true)"
        end

        @min = min
        @max = max
        self.value = @value
        invalidate # the scale moved even when the clamped value did not
      end

      # @return [Float] the progress, clamped into {#range} when assigned — so
      #   `bar.value = 999` on a `0..250` bar reads back as `250.0`.
      attr_reader :value

      # @param new_value [Numeric] clamped into {#range}.
      # @return [void]
      # @raise [ArgumentError] on NaN — typically `done.to_f / total` with a zero
      #   total, which wants {#indeterminate=} instead — or on a String `Float()`
      #   cannot parse.
      # @raise [TypeError] on `nil` and other types `Float()` refuses outright.
      def value=(new_value)
        new_value = Float(new_value)
        raise ArgumentError, "value must be a number, got NaN" if new_value.nan?

        new_value = new_value.clamp(@min, @max)
        return if @value == new_value

        @value = new_value
        invalidate
      end

      # @return [Float] {#value} as `0.0..1.0`. `1.0` when the range is empty.
      def fraction
        return 1.0 if @max == @min

        (@value - @min) / (@max - @min)
      end

      # @return [Integer] {#fraction} as `0..100`, floored — `100` means done and
      #   nothing else does, matching the painted bar exactly.
      def percent = scale(100)

      # Sets the color of both glyphs, live-resolved at paint time when given a
      # {Theme::Ref} (so it follows a {Screen#theme=} with no
      # {Component#on_theme_changed} hook).
      #
      #   bar.bar_color = Color::GREEN
      #   bar.bar_color = Theme.ref(:brand_ok)   # an app #custom token
      #
      # @param color [Color, Theme::Ref, Symbol, Integer, Array<Integer>, nil]
      #   coerced via {Color.coerce} unless it is a {Theme::Ref}; `nil` is the
      #   terminal default.
      # @return [void]
      # @raise [KeyError] when a {Theme::Ref} names a token the current theme
      #   lacks.
      def bar_color=(color)
        color = Color.coerce(color) unless color.is_a?(Theme::Ref)
        return if @bar_color == color

        color.resolve(screen.theme) if color.is_a?(Theme::Ref) # fail fast on a bad token

        @bar_color = color
        invalidate
      end

      # @return [Boolean] whether the sliding-block animation is showing.
      def indeterminate? = @indeterminate

      # Switches between the fill and the sliding block. {#value} keeps working
      # while indeterminate — it is simply not painted — so switching back shows
      # the progress that accumulated meanwhile.
      #
      # The animation only runs while the bar is {Component#attached? attached},
      # and stops on detach. It also keeps the event loop awake at
      # {INDETERMINATE_FPS}, so turn it off (or remove the bar) when the job ends.
      #
      # @param flag [Boolean] coerced; truthiness decides.
      # @return [void]
      def indeterminate=(flag)
        flag = flag ? true : false
        return if @indeterminate == flag

        @indeterminate = flag
        sync_ticker
        invalidate # the picture changes now, not on the next frame
      end

      # @return [void]
      def on_attached = sync_ticker

      # @return [void]
      def on_detached = sync_ticker

      # Paints the bar on the first row of {#rect} and blanks the rest.
      #
      # Deliberately not `super`: {Component#repaint}'s default blanks the
      # *whole* rect, which dirties every cell of the bar's own row before it is
      # painted over — so {Buffer#flush} re-emits the entire row every frame
      # instead of the one or two cells that actually moved.
      # @return [void]
      def repaint
        return if rect.empty?

        draw_text(rect.left, rect.top, StyledString.styled(glyphs(rect.width), fg: resolved_bar_color))
        clear_background(Rect.new(rect.left, rect.top + 1, rect.width, rect.height - 1)) if rect.height > 1
      end

      private

      # Filled cells out of `steps` — the rect width when painting, 100 for
      # {#percent}, so the bar and a {Label} showing the percentage can never
      # disagree about being done.
      # @param steps [Integer]
      # @return [Integer]
      def scale(steps)
        return 0 if fraction <= 0.0
        return steps if fraction >= 1.0
        return 0 if steps < 2 # no interior to land in; fills only when done

        (fraction * steps).floor.clamp(1, steps - 1)
      end

      # @param width [Integer] columns available.
      # @return [String] the row, `width` glyphs wide.
      def glyphs(width)
        start, length = @indeterminate ? block_at(width) : [0, scale(width)]
        [("░" * start), ("█" * length), ("░" * (width - start - length))].join
      end

      # Where the sliding block sits this frame: it enters at the left edge and
      # leaves at the right, one cell per frame, then loops. The period is one
      # short of `width + block` so at least one cell is always lit — a full
      # `width + block` blanks the bar for exactly one frame per cycle.
      # @param width [Integer] columns available.
      # @return [Array(Integer, Integer)] start column and length, clipped.
      def block_at(width)
        block = [width / BLOCK_DIVISOR, 1].max
        start = (@phase % (width + block - 1)) - (block - 1)
        first = [start, 0].max
        last = [start + block, width].min
        [first, last - first]
      end

      # @return [Color, nil]
      def resolved_bar_color
        @bar_color.is_a?(Theme::Ref) ? @bar_color.resolve(screen.theme) : @bar_color
      end

      # Brings the ticker in line with "animating and on screen". The sole writer
      # of `@ticker`, and idempotent, so the attach/detach hooks and
      # {#indeterminate=} are all the same call and a repeated `indeterminate =
      # true` cannot start a second one.
      # @return [void]
      def sync_ticker
        want = attached? && @indeterminate
        return if want == !@ticker.nil?

        if want
          @ticker = screen.event_queue.tick_fps(INDETERMINATE_FPS) do |tick|
            # The paint that already happened is frame 0; a ticker's first
            # firing is one interval later, so it is frame 1.
            @phase = tick + 1
            invalidate
          end
        else
          @ticker.cancel
          @ticker = nil
        end
      end
    end
  end
end
