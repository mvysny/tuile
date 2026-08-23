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
    # LEFT/RIGHT caret movement, CTRL+LEFT/CTRL+RIGHT word jumps, and the
    # `tab_stop?` flag (`focusable?` comes from {HasValue}).
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
    # The mutation pipeline is a template method: {#text=} and {#caret=}
    # detect no-ops, mutate state, fire {#on_change}, and invalidate.
    # Subclasses inject their own behavior via two protected hooks:
    #
    # - {#preprocess_text} — input filter (e.g. {TextField} truncates to
    #   fit `rect.width - 1`).
    # - {#preprocess_paste} — the same for {#handle_paste}, which lands a
    #   whole clipboard at the caret in one mutation.
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
        @on_key = nil
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

      # Optional interceptor consulted before the input's own key handling.
      # Receives the pressed key; return a truthy value to consume it (the
      # input then ignores that key), falsy to let normal editing proceed.
      #
      # The keyboard analog of {#on_change}: it lets app code layer behavior
      # onto an input without subclassing. The motivating case is an
      # autocomplete / slash-command overlay (a non-modal {Component::Popup}):
      # while it is open the interceptor claims Up/Down/Enter/ESC and forwards
      # them to the overlay's list, but lets ordinary characters fall through
      # so typing keeps editing the field (and {#on_change} keeps refilling the
      # list).
      # @return [Proc, Method, nil] one-arg callable, or nil.
      attr_accessor :on_key

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

      # Handles a key. An {#on_key} interceptor (if set) gets first refusal —
      # a truthy return consumes the key — otherwise it delegates to
      # {#handle_text_input_key}. Dispatch ({ScreenPane#handle_key}) only routes
      # keys here when this input is on the focus chain, so there is no
      # {#active?} gate.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        return true if @on_key&.call(key)

        handle_text_input_key(key)
      end

      # Inserts pasted text at the caret as **one** mutation, so {#on_change}
      # fires once for the whole paste rather than once per character.
      # {#preprocess_paste} filters it first.
      # @param text [String]
      # @return [Boolean] always true — a field consumes every paste, an empty
      #   one included.
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

      # Inserts `str` at the caret, leaving the caret behind it. The bulk
      # counterpart of a subclass's per-key insert.
      # @param str [String]
      # @return [Boolean] true if the text changed.
      def insert_text(str)
        return false if str.empty?

        new_text = @text.dup.insert(@caret, str)
        @caret += str.length
        self.text = new_text
        true
      end

      # Renders `text` on the field's background well, looked up from the
      # current {Screen#theme} at paint time: {Theme#active_bg_color} when this
      # input is on the active (focus) chain, {Theme#input_bg_color} otherwise —
      # visibly a field either way, distinctly highlighted when active.
      # @param text [String]
      # @return [StyledString] text on the field's background well.
      def background(text)
        StyledString.styled(text, bg: active? ? screen.theme.active_bg_color : screen.theme.input_bg_color)
      end

      # Input filter for {#text=}. Subclasses override to truncate or reject
      # invalid input. Default coerces to String.
      # @param new_text [String]
      # @return [String] possibly transformed text.
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

      # Dispatch hook for {#handle_key}. Handles ESC and the navigation keys
      # that have identical semantics in single-line and multi-line inputs:
      # LEFT/RIGHT arrows (one grapheme cluster per press, so a press always
      # moves), CTRL+LEFT/CTRL+RIGHT for word jumps. Subclasses
      # override to add their own keys (HOME/END, UP/DOWN, ENTER, BACKSPACE/
      # DELETE, printable insertion) and call `super` to fall back to the
      # common navigation handling.
      # @param key [String]
      # @return [Boolean] true if the key was handled.
      def handle_text_input_key(key)
        case key
        when Keys::LEFT_ARROW then self.caret = cluster_boundary_before(@caret)
        when Keys::RIGHT_ARROW then self.caret = cluster_boundary_after(@caret)
        when Keys::CTRL_LEFT_ARROW then self.caret = word_left
        when Keys::CTRL_RIGHT_ARROW then self.caret = word_right
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
      def delete_before_caret
        return if @caret.zero?

        start = cluster_boundary_before(@caret)
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
