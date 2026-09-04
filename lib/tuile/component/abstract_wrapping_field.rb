# frozen_string_literal: true

module Tuile
  class Component
    # Abstract base for a field that **wraps one editor completely**: it carries
    # a typed {HasValue#value} but paints nothing itself, handing the whole UI to
    # a single {AbstractStringField} it owns and hides. Subclass it by passing
    # the editor to `super` and defining the conversion both ways:
    #
    #   class IntegerField < Component::AbstractWrappingField
    #     def initialize = super(TextField.new)
    #
    #     def value = Integer(editor.text, 10) rescue nil
    #
    #     def value=(new_value)
    #       editor.text = new_value.nil? ? "" : new_value.to_s
    #       editor.caret = editor.text.length
    #     end
    #
    #     def empty_value = nil
    #   end
    #
    # Everything else arrives already wired: the editor is added as the single
    # child and positioned across {Component#rect}, focus forwards into it, it
    # sits on this field's one background well, and {#placeholder} /
    # {#on_enter} / {#cursor_position} / {#clear} are re-exposed here so an app
    # never addresses it. Give the field a single-row rect.
    #
    # == The editor is private machinery
    # There is no public accessor — {#editor} is protected, for subclasses — and
    # that is the point: swapping it would break the conversion. **An app never
    # addresses the editor**; what it needs is either already delegated here or
    # earns a forwarder here. It is still in `children`, because the tree is
    # reported honestly, but that is not an invitation.
    #
    # A **spec** is the exception, and it has a sanctioned path — driving the
    # editor is how a test reaches a state no public setter produces:
    #
    #   editor = Testing.get(Component::TextField, in: field)
    #   editor.text = "-"          # bad input; field.value still reads nil
    #
    # A knob that is *editor-shaped* rather than a concept of this field's own
    # domain is **not** forwarded, and the subclass sets it on its editor
    # instead:
    #
    #   def initialize
    #     super(TextField.new)
    #     editor.max_text_length = 20   # an internal cap, not part of my surface
    #   end
    #
    # == Committing: leaving the widget, and ENTER
    # {#commit} fires on both commit gestures. Leaving the focus chain is one —
    # the *field*'s, not its editor's, which is left on every hop within a
    # widget. ENTER is the other, because a form whose default button is reached
    # by ENTER never moves focus at all. Override it to canonicalize a buffer
    # the user typed loosely:
    #
    #   def commit = (self.value = value unless value.nil?)   # rewrite in the canonical form
    #
    # ENTER is committed and then **left to keep bubbling**, so a scope's
    # default button still sees it; only an {#on_enter} of this field's own
    # consumes it, which is {TextField#on_enter}'s existing contract.
    #
    # == Implementation details
    # - **{HasValue#value} and {#value=} raise until overridden.** The inherited
    #   pair stores into `@value` and never touches the editor, so a subclass
    #   that defined only one would silently half-work.
    # - **{HasValue#empty_value} is called during construction**, to seed the
    #   change guard, so it must not depend on subclass state that `super` has
    #   not set yet. In practice it is a constant per class.
    # - **The editor's `on_change` and `on_enter` slots are claimed** — for that
    #   guard, and to commit before an app's ENTER handler runs. A slot cannot
    #   be shared, so a subclass reacting to buffer edits overrides
    #   {#on_input_change} (every edit), {#value=} or {#commit} rather than
    #   reassigning either.
    # - **Not for a field whose editor is a *filter*.** This base assumes the
    #   buffer is a rendering of the value, so an edit may change the value.
    #   {ComboBox} breaks both halves — its text is a transient query and only a
    #   commit moves its value — which is the same line {HasBadInput} draws.
    #
    # UI-thread-confined, like every component (see {Screen}).
    class AbstractWrappingField < Component
      include HasValue
      include HasPlaceholder

      # @param editor [AbstractStringField] the editor to wrap; becomes this
      #   field's single child and is never swapped.
      # @raise [TypeError] unless `editor` is an {AbstractStringField}.
      def initialize(editor)
        super()
        raise TypeError, "expected AbstractStringField, got #{editor.inspect}" unless editor.is_a?(AbstractStringField)

        @editor = editor
        @last_value = empty_value
        @on_enter = nil
        # One widget, one surface: the editor paints no well of its own, so this
        # field's bg_color reaches the cells the editor paints.
        editor.bg_color = BG_INHERIT
        editor.on_change = ->(_text) { editor_changed }
        add_child(editor, at: 0)
      end

      # @return [Object] the typed value, parsed from the editor's buffer.
      # @raise [NotImplementedError] unless the subclass overrides it.
      def value = raise(NotImplementedError, "#{self.class} must implement value")

      # Writes `new_value` into the editor's buffer.
      # @param new_value [Object]
      # @return [void]
      # @raise [NotImplementedError] unless the subclass overrides it.
      def value=(new_value)
        raise(NotImplementedError, "#{self.class} must implement value=")
      end

      # Empties the *input*, not just the value — a field holding bad input
      # already reads {HasValue#empty_value}, so clearing through {#value=} could
      # leave the glyphs on screen ({HasBadInput}).
      # @return [void]
      def clear = editor.clear

      # @return [String, nil] the hint the editor paints while empty
      #   ({HasPlaceholder}).
      def placeholder = editor.placeholder

      # @param text [String, nil]
      # @return [void]
      # @raise [TypeError] unless `text` is a String or nil.
      def placeholder=(text)
        editor.placeholder = text
      end

      # @return [Proc, Method, nil] fired when ENTER is pressed, *after*
      #   {#commit}; see {TextField#on_enter}.
      attr_reader :on_enter

      # @param callback [Proc, Method, nil]
      # @return [void]
      def on_enter=(callback)
        @on_enter = callback
        # Wrapped rather than forwarded, so an app's ENTER handler reads a
        # committed buffer. A nil callback leaves the editor's own slot nil,
        # which is what keeps ENTER *bubbling* — see {#handle_key}.
        editor.on_enter = callback && lambda do
          commit
          callback.call
        end
      end

      # ENTER commits, and is then left to keep bubbling.
      #
      # Committing here covers the case the editor declines: with no
      # {#on_enter} set it does not consume ENTER, so the key arrives on this
      # field by bubbling and would otherwise reach a form's default button
      # while this field still held an uncommitted buffer — the same ordering
      # trap as acting before `super` in a mouse handler. The key is
      # deliberately **not** consumed, so that default button still fires.
      # @param key [String]
      # @return [Boolean]
      def handle_key(key)
        commit if key == Keys::ENTER
        super
      end

      # @return [Point, nil] the editor's caret — the hardware cursor is
      #   delegated to it.
      def cursor_position = editor.cursor_position

      # Runs {#commit} on the falling edge, i.e. when this field leaves the focus
      # chain. Moving focus *within* a widget keeps it active, so a future
      # multi-editor field inherits the same semantics unchanged.
      # @param flag [Boolean]
      # @return [void]
      def active=(flag)
        was = active?
        super
        commit if was && !active?
      end

      # @return [void]
      def on_focus
        super
        # The editor is what actually edits, so it takes the focus this field was
        # given — the field itself has no keys of its own.
        screen.focused = editor if editor.focusable?
      end

      # @param new_rect [Rect]
      # @return [void]
      def rect=(new_rect)
        super
        layout(editor)
      end

      protected

      # @return [AbstractStringField] the wrapped editor.
      attr_reader :editor

      # Called on a commit gesture — the field leaving the focus chain, or
      # ENTER; no-op by default. This is the commit point a canonicalizing
      # field rewrites its buffer from.
      # @return [void]
      def commit = nil

      # Called on every buffer edit, however the characters arrived — a typed
      # key, a paste, or a {#value=} of this field's own. No-op by default;
      # override it to drop state that describes the *previous* buffer, as a
      # field latching whether its input has settled must ({HasBadInput}).
      # @return [void]
      def on_input_change = nil

      # Places the editor across the whole rect; override to reserve cells for a
      # face of your own.
      # @param editor [Component]
      # @return [void]
      def layout(editor) = (editor.rect = rect)

      # The field well the face sits on — the editor is marked
      # {Component::BG_INHERIT}, so this one covers it (exactly one well per
      # widget) and {Component#bg_color} set here reaches the cells it paints.
      # @return [Color]
      def default_bg_color = active? ? screen.theme.active_bg_color : screen.theme.input_bg_color

      private

      # @return [void]
      def editor_changed
        on_input_change
        fire_if_changed
      end

      # Re-emits {HasValue#on_value_change}, but only when {#value} differs from
      # the last one fired — so a buffer edit that leaves the value alone
      # (`"7"`→`"07"`) stays silent.
      # @return [void]
      def fire_if_changed
        v = value
        return if v == @last_value

        @last_value = v
        on_value_change&.call(v)
      end
    end
  end
end
