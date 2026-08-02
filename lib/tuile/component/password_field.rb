# frozen_string_literal: true

module Tuile
  class Component
    # A {TextField} that paints one mask glyph per character instead of the
    # text. Editing, caret, clicks and horizontal scrolling are the field's,
    # unchanged:
    #
    #   pf = Component::PasswordField.new
    #   pf.rect  = Rect.new(0, 0, 20, 1)
    #   pf.value                          # => the plaintext String
    #   pf.mask_char = "•"                # default "*"
    #   pf.revealed  = true               # show the plaintext, e.g. behind a Checkbox
    #
    # A password's value *is* its text, so this subclasses {TextField} rather
    # than composing one the way {IntegerField} does — the delta is presentation
    # only, and it lands entirely on {TextField#display_text}.
    #
    # == What it hides, and what it doesn't
    # The plaintext is an ordinary Ruby `String`: not pinned, not wiped, not
    # kept out of GC. Anything stronger needs a frozen-buffer type and the
    # cooperation of every consumer, which is out of scope for a widget.
    #
    # The mask shows the text's *length* — accepted, since a caret has to sit
    # somewhere. Its *word structure* is hidden: CTRL+LEFT / CTRL+RIGHT jump to
    # the ends while masked instead of hopping the spaces a watcher could then
    # read off the caret. They resume word-jumping when {#revealed}.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class PasswordField < TextField
      def initialize
        super
        @mask_char = "*"
        @revealed = false
      end

      # @return [String] the glyph painted per character; `"*"` by default.
      attr_reader :mask_char

      # The default is `"*"` rather than a prettier `"•"` because U+2022 is
      # East-Asian-*Ambiguous*: a CJK-configured terminal draws it two columns
      # wide, shifting every column past the caret. Validation can't catch that
      # one — Tuile measures Ambiguous as 1 by construction — so the default
      # carries it, and this setter is the knob for someone who knows their
      # terminal.
      # @param char [String] one grapheme cluster, one column wide.
      # @return [void]
      # @raise [TypeError] unless `char` is a String.
      # @raise [ArgumentError] if `char` isn't exactly one single-column
      #   grapheme cluster — a multi-cluster mask would break the
      #   one-glyph-per-character contract {TextField#display_text} rests on,
      #   a wide one the column axis.
      def mask_char=(char)
        raise TypeError, "expected String, got #{char.inspect}" unless char.is_a?(String)
        raise ArgumentError, "expected one grapheme cluster, got #{char.inspect}" unless single_cluster?(char)
        raise ArgumentError, "expected a 1-column glyph, got #{char.inspect}" unless Buffer.display_width(char) == 1

        return if @mask_char == char

        @mask_char = char
        invalidate
      end

      # @return [Boolean] whether the plaintext is shown; `false` by default.
      attr_reader :revealed

      # @return [Boolean] {#revealed} in predicate form.
      def revealed? = @revealed

      # Shows or re-masks the plaintext. There is no built-in reveal *button* —
      # a TTY field has no room for an in-field affordance — so an app flips
      # this from a key binding or a sibling {Checkbox}.
      # @param flag [Object] anything; truthiness decides.
      # @return [void]
      def revealed=(flag)
        flag = flag ? true : false
        return if @revealed == flag

        @revealed = flag
        # The plaintext and the mask differ in *columns* (a CJK passphrase is
        # wider than its mask), so the scroll window has to be recomputed —
        # the caret index it must keep visible has not moved.
        adjust_left_column
        invalidate
      end

      protected

      # @return [String] the mask, one glyph per character, unless {#revealed}.
      def display_text = revealed? ? super : @mask_char * @text.length

      private

      # @param char [String]
      # @return [Boolean]
      def single_cluster?(char) = char.each_grapheme_cluster.take(2).size == 1

      # @return [Integer] caret target for CTRL+LEFT: the start, while masked.
      def word_left = revealed? ? super : 0

      # @return [Integer] caret target for CTRL+RIGHT: the end, while masked.
      def word_right = revealed? ? super : @text.length
    end
  end
end
