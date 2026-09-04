# frozen_string_literal: true

module Tuile
  class Component
    # Abstract base for the **String-valued** editable text components
    # ({TextField}, {TextArea}): a field whose {HasValue#value} *is* its text.
    # A field whose value is a different type (an `Integer`, a domain object)
    # *composes* one of these rather than subclassing it — subclassing would
    # drag this String-typed `text`/`value` seam onto its face alongside the
    # real typed one.
    #
    # Holds the shared state — a mutable {#text} buffer, a {#caret} index,
    # {#on_change} and {#on_escape} callbacks — and the keyboard machinery
    # that single-line and multi-line inputs both need: ESC handling,
    # LEFT/RIGHT caret movement, CTRL+LEFT/CTRL+RIGHT word jumps, CTRL+W
    # word-delete, and the `tab_stop?` flag (`focusable?` comes from
    # {HasValue}).
    #
    # {#caret} counts *characters* into {#text} but may only sit *between*
    # grapheme clusters — the glyphs a terminal draws. Both write sites snap it
    # forward onto the enclosing cluster's end, and every edit steps by a whole
    # cluster:
    #
    #   f.text  = "e\u{0301}x"   # a decomposed e-acute then "x": 3 chars, 2 glyphs
    #   f.caret = 1              # into the middle of the e-acute …
    #   f.caret                  # => 2, its end — where the caret already drew
    #   f.handle_key(Keys::BACKSPACE)
    #   f.text                   # => "x": the whole glyph went, not its accent
    #
    # Insertion stays character-native, so `String#insert` merges a typed
    # combining mark into its base; {#text=}'s snap covers the case where that
    # re-segments the text around the caret.
    #
    # Subclasses implement the layout-specific pieces ({#cursor_position},
    # {#repaint}) and add their own keys (HOME/END, ENTER, UP/DOWN,
    # printable insertion) by overriding the protected
    # {#handle_text_input_key} hook — `super` falls through to the common
    # navigation handling.
    #
    # == Customizing a field is subclassing it, and there are two seams
    # To change what **keys** do, override {#handle_text_input_key}; to
    # constrain what the buffer may **hold**, override {#insert_text}, which
    # every insertion runs through — typed, pasted, or the ENTER newline:
    #
    #   class HexField < TextField
    #     protected
    #
    #     # ENTER submits instead of falling through to the parent.
    #     def handle_text_input_key(key)
    #       return super unless key == Keys::ENTER
    #
    #       submit(text)
    #       true
    #     end
    #
    #     # Hex digits only — and a paste of "12zz" lands nothing, not "12".
    #     def insert_text(str)
    #       return false unless @text.dup.insert(@caret, str).match?(/\A\h*\z/)
    #
    #       super
    #     end
    #   end
    #
    # Both compose through `super`, which is why they are overrides rather than
    # the callback slot this class carried until 0.15.0: two behaviors could not
    # share one slot, and a filter written on a *key* callback let the same
    # characters in through a paste (`D_input_filters`, book ch7).
    #
    # The mutation pipeline is a template method: {#text=} and {#caret=}
    # detect no-ops, mutate state, fire {#on_change}, and invalidate.
    # Subclasses inject their own behavior via four protected hooks:
    #
    # - {#insert_text} — **the one filter seam**: every insertion runs through
    #   it, typed or pasted, so what the buffer may hold is decided here.
    # - {#preprocess_text} — filter for a whole assignment to {#text=},
    #   which insertion does *not* pass through.
    # - {#preprocess_paste} — sanitizer for {#handle_paste}, run before the
    #   clipboard reaches {#insert_text} ({TextField} keeps its first line).
    # - {#on_text_mutated} / {#on_caret_mutated} — post-mutation side
    #   effects (e.g. {TextArea} invalidates its wrap cache and scrolls to
    #   keep the caret visible).
    class AbstractStringField < Component
      include HasValue

      def initialize
        super
        @text = +""
        @caret = 0
        @on_change = nil
        @on_value_change = nil
        @on_escape = method(:default_on_escape)
      end

      # @return [String] current text contents.
      attr_reader :text

      # A text component's value *is* its text: {#value}/{#value=} are the
      # {HasValue} seam over the same buffer as {#text}/{#text=}, so a form can
      # drive it alongside typed fields. `text` stays the text-native name.
      # @return [String]
      def value = text

      # @param new_value [String, #to_s]
      # @return [void]
      def value=(new_value)
        self.text = new_value.to_s
      end

      # `""` (not `nil`): a text field is empty when its buffer is blank.
      # @return [String]
      def empty_value = ""

      # @return [Integer] caret index in `0..text.length`, counting characters
      #   and always on a grapheme-cluster boundary (see the class doc).
      attr_reader :caret

      # Optional callback fired whenever {#text} changes. Receives the new text
      # as a single argument. Not fired by {#caret=} (text unchanged) and not
      # fired when a setter is a no-op.
      # @return [Proc, Method, nil] one-arg callable, or nil.
      attr_accessor :on_change

      # Callback fired when ESC is pressed. Defaults to a closure that clears
      # focus (`screen.focused = nil`) so ESC visibly cancels text entry instead
      # of bubbling to the parent — and, in particular, instead of reaching the
      # screen's default ESC-to-quit handler. Set to nil to let ESC fall through
      # to the parent again; set to any other callable to replace the default.
      # @return [Proc, Method, nil] no-arg callable, or nil.
      attr_accessor :on_escape

      def tab_stop? = true

      # Sets the text. Runs {#preprocess_text} first (subclasses may filter or
      # truncate). Caret is clamped to the new text length, then snapped back
      # onto a cluster boundary of the *new* text. Fires {#on_change} only on a
      # real change.
      # @param new_text [String]
      def text=(new_text)
        new_text = preprocess_text(new_text)
        return if @text == new_text

        @text = +new_text
        @caret = snap_to_cluster(@caret.clamp(0, @text.length))
        on_text_mutated
        invalidate
        @on_change&.call(@text)
        on_value_change&.call(@text)
      end

      # Clamps to `0..text.length`, then snaps forward onto a grapheme-cluster
      # boundary, so an index that fell inside a cluster reads back as that
      # cluster's end. Fires the {#on_caret_mutated} hook for subclasses (e.g.
      # {TextArea} scrolls).
      # @param new_caret [Integer]
      def caret=(new_caret)
        new_caret = snap_to_cluster(new_caret.clamp(0, @text.length))
        return if @caret == new_caret

        @caret = new_caret
        on_caret_mutated
        invalidate
      end

      # Handles a key, by delegating to the {#handle_text_input_key} hook a
      # subclass overrides. Dispatch ({ScreenPane#handle_key}) only routes keys
      # here when this input is on the focus chain, so there is no {#active?}
      # gate.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key) = handle_text_input_key(key)

      # Inserts pasted text at the caret as **one** mutation, so {#on_change}
      # fires once for the whole paste rather than once per character.
      # {#preprocess_paste} filters it first.
      # @param text [String]
      # @return [Boolean] always true — a field consumes every paste: an empty
      #   one, and one its {#insert_text} rejects wholesale.
      def handle_paste(text)
        insert_text(preprocess_paste(text))
        true
      end

      protected

      # Input filter for {#handle_paste}, the paste-side counterpart of
      # {#preprocess_text}. Strips the C0 control characters a text buffer
      # cannot hold — a raw `\e` or `\t` reaching {Buffer} would move the real
      # terminal cursor mid-frame — keeping `\n`, and turning a tab into a
      # single space so pasted code keeps its word gaps. {TextField} narrows it
      # further; an app wanting tab *expansion* overrides {#handle_paste}.
      # @param text [String]
      # @return [String]
      def preprocess_paste(text) = text.tr("\t", " ").gsub(/[\x00-\x09\x0b-\x1f\x7f]/, "")

      # Inserts `str` at the caret, leaving the caret behind it.
      #
      # **Every insertion lands here** — a typed character, the ENTER newline
      # and a whole pasted clipboard alike — so a field constrains its contents
      # by overriding this, and one override covers typing and pasting both:
      #
      #   def insert_text(str)      # hex digits only, in a TextField subclass
      #     return false unless @text.dup.insert(@caret, str).match?(/\A\h*\z/)
      #
      #     super
      #   end
      #
      # Test the whole resulting buffer, as above, and not the fragment being
      # inserted: sieving per character turns a pasted `"1,5"` into the
      # plausible, wrong `"15"`, where an all-or-nothing test drops it — which
      # is also what typing the comma does. Filtering at all works only for a
      # grammar every valid value can be *typed through*; one where it can't
      # (a date — `"2020-13-45"` is well-formed at every character) reports bad
      # input rather than filtering it (`D_input_filters`, book ch7).
      #
      # {#text=} does *not* pass through here: only user input is filtered, so a
      # programmatic {HasValue#value=} may still write what no key types.
      # @param str [String]
      # @return [Boolean] true if the text changed.
      def insert_text(str)
        return false if str.empty?

        new_text = @text.dup.insert(@caret, str)
        @caret += str.length
        self.text = new_text
        true
      end

      # The field's background well, looked up from the current {Screen#theme}
      # at paint time: {Theme#active_bg_color} while this input is on the active
      # (focus) chain, {Theme#input_bg_color} otherwise — visibly a field either
      # way, distinctly highlighted when focused. An app overrides the pair by
      # setting {Component#bg_color}, which wins over this.
      #
      # Unconditional on purpose. A field used as the face of a composed one
      # ({Component::ComboBox}, {Component::IntegerField} …) is *told* to drop
      # its well — that widget assigns {Component::BG_INHERIT} at construction,
      # since it owns the surface and a second well would make its own
      # {Component#bg_color} inert over the very cells this field paints.
      # @return [Color]
      def default_bg_color = active? ? screen.theme.active_bg_color : screen.theme.input_bg_color

      # Input filter for a whole assignment to {#text=}. Nothing overrides it
      # today; a subclass that does is filtering the *programmatic* setter, not
      # user input — that is {#insert_text}.
      # @param new_text [String]
      # @return [String] possibly transformed text; the default coerces to String.
      def preprocess_text(new_text) = new_text.to_s

      # The one measurement primitive both inputs share: a caret index counts
      # characters, but every rect, cursor and click counts columns, and only
      # this converts between them.
      # @param str [String]
      # @return [Integer] `str`'s width in terminal columns, measured per
      #   grapheme cluster — so a combining mark adds nothing and a fullwidth
      #   glyph adds two.
      def columns_of(str) = str.each_grapheme_cluster.sum { |g| Buffer.display_width(g) }

      # Hook called after {#text} has been mutated, before invalidation /
      # {#on_change}. Default no-op. Subclasses use this to invalidate caches
      # ({TextArea}'s wrap cache) and update derived state.
      # @return [void]
      def on_text_mutated; end

      # Hook called after {#caret} has been mutated, before invalidation.
      # Default no-op. Subclasses use this to keep the caret visible
      # ({TextArea}'s vertical scroll).
      # @return [void]
      def on_caret_mutated; end

      # Dispatch hook for {#handle_key}. Handles ESC and the editing keys that
      # have identical semantics in single-line and multi-line inputs:
      # LEFT/RIGHT arrows (one grapheme cluster per press, so a press always
      # moves), CTRL+LEFT/CTRL+RIGHT for word jumps, and CTRL+W, which deletes
      # exactly what CTRL+LEFT would have skipped over (readline's
      # `unix-word-rubout`). Subclasses override to add their own keys (HOME/END,
      # UP/DOWN, ENTER, CTRL+U, BACKSPACE/DELETE, printable insertion) and call
      # `super` to fall back to the common handling.
      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_text_input_key(key)
        case key
        when Keys::LEFT_ARROW then self.caret = cluster_boundary_before(@caret)
        when Keys::RIGHT_ARROW then self.caret = cluster_boundary_after(@caret)
        when Keys::CTRL_LEFT_ARROW then self.caret = word_left
        when Keys::CTRL_RIGHT_ARROW then self.caret = word_right
        when Keys::CTRL_W then delete_back_to(word_left)
        when Keys::ESC
          return false if @on_escape.nil?

          @on_escape.call
        else
          return false
        end
        true
      end

      # Removes the whole grapheme cluster before the caret — one press, one
      # glyph, whatever it is built from (a ZWJ emoji family and a three-jamo
      # Hangul syllable each go whole).
      # @return [void]
      def delete_before_caret = delete_back_to(cluster_boundary_before(@caret))

      # Removes the text between `index` and the caret, leaving the caret at
      # `index` — one mutation, so {#on_change} fires once.
      #
      # `index` is snapped forward onto a grapheme-cluster boundary, so a
      # caller may compute it by counting characters.
      # @param index [Integer] a {#text} index; clamped to `0..caret`.
      # @return [void]
      def delete_back_to(index)
        start = snap_to_cluster(index.clamp(0, @caret))
        return if start == @caret

        new_text = @text.dup
        new_text.slice!(start...@caret)
        @caret = start
        self.text = new_text
      end

      # Removes the whole grapheme cluster at the caret.
      # @return [void]
      def delete_at_caret
        return if @caret >= @text.length

        new_text = @text.dup
        new_text.slice!(@caret...cluster_boundary_after(@caret))
        self.text = new_text
      end

      private

      # @param index [Integer] a {#text} index in `0..text.length`.
      # @return [Integer] the smallest grapheme-cluster boundary `>= index`.
      def snap_to_cluster(index)
        offset = 0
        @text.each_grapheme_cluster do |g|
          return offset if offset >= index

          offset += g.length
        end
        offset
      end

      # @param index [Integer]
      # @return [Integer] the greatest grapheme-cluster boundary `< index`, or
      #   0 at the start of the text.
      def cluster_boundary_before(index)
        last = 0
        offset = 0
        @text.each_grapheme_cluster do |g|
          offset += g.length
          return last if offset >= index

          last = offset
        end
        last
      end

      # @param index [Integer]
      # @return [Integer] the smallest grapheme-cluster boundary `> index`, or
      #   `text.length` at the end of the text.
      def cluster_boundary_after(index)
        offset = 0
        @text.each_grapheme_cluster do |g|
          offset += g.length
          return offset if offset > index
        end
        offset
      end

      # Default {#on_escape} action: clear focus. Component deactivates; user
      # can re-focus by clicking or tabbing back in.
      # @return [void]
      def default_on_escape
        screen.focused = nil
      end

      # Caret target for ctrl+left: skip whitespace going left, then a run of
      # non-whitespace. Lands at the beginning of the current word, or the
      # beginning of the previous word if already there.
      # @return [Integer]
      def word_left
        c = @caret
        c -= 1 while c.positive? && @text[c - 1].match?(/\s/)
        c -= 1 while c.positive? && !@text[c - 1].match?(/\s/)
        c
      end

      # Caret target for ctrl+right: skip non-whitespace going right, then a
      # run of whitespace. Lands at the beginning of the next word, or at the
      # end of the text if no further word exists.
      # @return [Integer]
      def word_right
        c = @caret
        c += 1 while c < @text.length && !@text[c].match?(/\s/)
        c += 1 while c < @text.length && @text[c].match?(/\s/)
        c
      end
    end
  end
end
