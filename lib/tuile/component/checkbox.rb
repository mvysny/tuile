# frozen_string_literal: true

module Tuile
  class Component
    # A boolean input on one row. Space, Enter or a left click toggles it:
    #
    #   [x] Enable syslog forwarding
    #   [ ] Enable syslog forwarding
    #
    #   cb = Component::Checkbox.new("Enable syslog forwarding", value: true)
    #   cb.on_value_change = ->(on) { config.syslog = on }
    #   cb.toggle       # unchecks it, firing the listener with false
    #   cb.checked?     # => false
    #
    # {#value} is the canonical seam ({HasValue}), always `true`/`false` and
    # never `nil`; {#checked?} / {#checked=} / {#toggle} are the domain-word face
    # over it — one piece of state, four names. Unchecked is the
    # {#empty_value}, so a fresh checkbox is {HasValue#empty? empty} and
    # {HasValue#clear} unchecks.
    #
    # Space and Enter both toggle — same as a checkable row in a
    # {Component::List} ({CheckboxGroup}, {RadioGroup}), so the gesture reads the
    # same standalone and grouped. A focused checkbox therefore *consumes* Enter:
    # a form's Enter-to-submit on an ancestor won't see it, exactly as with a
    # focused {Button} or {TextArea}. Which widget lets Enter through is per
    # widget, never a framework guarantee — book ch5's Enter table is the list.
    #
    # A tab stop, so Tab lands on it, and the widget highlights while on the focus
    # chain. Assign a {#rect} (typically from the surrounding {Layout}) at least
    # `caption.display_width + 4` wide; a narrower one ellipsizes the caption, a
    # wider one leaves a dead tail — see {#extent}.
    #
    # == Implementation details
    # The glyphs are a house convention rather than constants: three columns plus
    # a trailing space (`[x] `, `[ ] `), ASCII because `☑`/`☐` are absent from
    # most monospace fonts and the fallback glyph bleeds over its cell. A widget
    # painting checkbox-like rows without instantiating a Checkbox — checkable
    # rows in a {Component::List} — repeats those literals to match.
    class Checkbox < Component
      include Component::HasValue
      include Component::HasCaption

      # @param caption [String, StyledString, nil] the label, coerced as
      #   {HasCaption#caption=} coerces it.
      # @param value [Boolean] initial state. Assigned through {#value=}, which
      #   also seeds the backing ivar — an unseeded checkbox would read `nil` and
      #   so report itself non-{HasValue#empty? empty} while fresh.
      def initialize(caption = nil, value: false)
        super()
        self.caption = caption
        self.value = value
      end

      def tab_stop? = true

      # @return [Boolean] `false` — {HasValue#empty?} means unchecked.
      def empty_value = false

      # Coerces to `true`/`false` before storing, so the two-state invariant holds
      # whatever a caller assigns — and `cb.value = nil` on a fresh checkbox is
      # the no-op it looks like rather than a spurious change event.
      # @param new_value [Object] anything; truthiness decides.
      # @return [void]
      def value=(new_value)
        super(new_value ? true : false)
      end

      # @return [Boolean] {#value} under its domain word — `license.checked?`
      #   reads better than `license.value`. Not a second piece of state.
      def checked? = value

      # {#value=} under its domain word. A delegator rather than an `alias`, so it
      # keeps routing through the one write path even if a subclass overrides
      # {#value=} (an `alias` would freeze this onto the body defined here).
      # @param new_value [Object] anything; truthiness decides.
      # @return [void]
      def checked=(new_value)
        self.value = new_value
      end

      # Flips {#value}.
      # @return [void]
      def toggle = (self.value = !value)

      # The cells the widget actually paints: one row, `caption.display_width + 4`
      # columns, clipped to {#rect}. A form column routinely hands a checkbox a
      # 40-column rect for a 22-column `[ ] Enable syslog forwarding` — the extent
      # is those 22 columns.
      #
      # Both the focus highlight and the click hit test use it, so a click on the
      # blank tail — or on a lower row, when the rect is taller than one — does
      # not toggle. It still *focuses*: {Component#handle_mouse}'s click-to-focus
      # is ungated by geometry, and the tail is the field's own row.
      #
      # The extent ignores {Component#bg_color}: an inherited tint paints the dead
      # tail, but a hit test that silently widened with a background would be a
      # mode switch invisible in the code and untestable by inspection.
      # @return [Rect]
      def extent = Rect.new(rect.left, rect.top, [caption.display_width + 4, rect.width].min, 1)

      # Toggles on Space or Enter. Every other key is left unhandled so it bubbles
      # to an ancestor.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return false unless [" ", Keys::ENTER].include?(key)

        toggle
        true
      end

      # Toggles on a left click within {#extent}; `super` runs first, so a click
      # anywhere in {#rect} still focuses.
      # @param event [MouseEvent]
      # @return [void]
      def handle_mouse(event)
        super
        return unless event.button == :left && extent.contains?(event.point)

        toggle
      end

      # @return [void]
      def repaint
        super
        return if rect.empty?

        label = (StyledString.plain(value ? "[x] " : "[ ] ") + caption).ellipsize(rect.width)
        label = label.with_bg(screen.theme.active_bg_color) if active?
        draw_line(rect.left, rect.top, label)
      end
    end
  end
end
