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
    #     def set_value(new_value, from_user:)
    #       editor.set_value(new_value.nil? ? "" : new_value.to_s, from_user:)
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
    #   editor.value = "-"         # bad input; field.value still reads nil
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
    #   def commit = (set_value(value, from_user: true) unless value.nil?)   # rewrite canonically
    #
    # ENTER is committed and then **left to keep bubbling**, so a scope's
    # default button still sees it; only an {#on_enter} of this field's own
    # consumes it, which is {TextField#on_enter}'s existing contract.
    #
    # == When the value notice fires
    # Per edit by default. A field whose grammar is not prefix-closed sets
    # {#notify_on_edit?} to `false` and lets the notice settle onto those same
    # two gestures, so a form is never handed a half-typed date that happens to
    # parse ({DateField}, {TimeField}).
    #
    # == Who made the change
    # The editor's own event says whether the user moved the buffer, and this
    # field's notice passes that on: a subclass writes the editor through
    # {AbstractStringField#set_value} with the `from_user:` it was handed, and
    # the edit route relays it. The commit gestures announce as the user's —
    # an approximation for the one commit code can cause, a programmatic
    # `screen.focused =` moving focus off this field.
    #
    # == Implementation details
    # - **{HasValue#value} and {#set_value} raise until overridden.** The inherited
    #   pair stores into `@value` and never touches the editor, so a subclass
    #   that defined only one would silently half-work.
    # - **{HasValue#empty_value} is called during construction**, to seed the
    #   change guard, so it must not depend on subclass state that `super` has
    #   not set yet. In practice it is a constant per class.
    # - **The editor's `on_value_change` and `on_enter` slots carry this field's own
    #   listeners** — for that guard, and to commit before an app's ENTER handler
    #   runs. They are lists, so nothing an app adds displaces them; a subclass
    #   reacting to buffer edits still overrides {#handle_editor_change} (every
    #   edit), {#set_value} or {#commit}, which run in a defined order.
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
        # Held so the transition block can unsubscribe the same object it added:
        # a lambda is only equal to itself.
        @enter_bridge = lambda do
          commit_and_notify
          on_enter.fire(EnterEvent.new(source: self))
        end
        # One widget, one surface: the editor paints no well of its own, so this
        # field's well covers it and its bg_color reaches the cells the editor paints.
        editor.bg_color = ComponentBackground::INHERIT
        bg.default_color = ComponentBackground::INPUT_WELL
        editor.on_value_change do |e|
          handle_editor_change
          fire_if_changed(from_user: e.from_user?) if notify_on_edit?
        end
        add_child(editor, at: 0)
      end

      # @return [Object] the typed value, parsed from the editor's buffer.
      # @raise [NotImplementedError] unless the subclass overrides it.
      def value = raise(NotImplementedError, "#{self.class} must implement value")

      # Writes `new_value` into the editor's buffer, passing `from_user` on to
      # {AbstractStringField#set_value}.
      # @param new_value [Object]
      # @param from_user [Boolean] see {HasValue#set_value}.
      # @return [void]
      # @raise [NotImplementedError] unless the subclass overrides it.
      def set_value(new_value, from_user:)
        raise(NotImplementedError, "#{self.class} must implement set_value")
      end

      # Empties the *input*, not just the value — a field holding bad input
      # already reads {HasValue#empty_value}, so clearing through {#value=} could
      # leave the glyphs on screen ({HasBadInput}).
      # @return [void]
      def clear
        editor.clear
        # Announced here rather than through the editor's change, so a field
        # holding its notice ({#notify_on_edit?}) still reports an emptying as
        # it happens: emptying is not a half-typed prefix.
        fire_if_changed(from_user: false)
      end

      # @return [String, nil] the hint the editor paints while empty
      #   ({HasPlaceholder}).
      def placeholder = editor.placeholder

      # @param text [String, nil]
      # @return [void]
      # @raise [TypeError] unless `text` is a String or nil.
      def placeholder=(text)
        editor.placeholder = text
      end

      # What {#on_enter} fires.
      #
      # @!attribute [r] source
      #   @return [AbstractWrappingField] the field ENTER reached.
      EnterEvent = Data.define(:source) { include Tuile::Event }

      # @!method on_enter
      #   Fired with an {EnterEvent} when ENTER is pressed, *after* {#commit};
      #   see {TextField#on_enter}.
      #
      #   **Empty means the field declines ENTER**, which keeps it bubbling to
      #   the scope's default button — see {#handle_key?}. The editor's own slot
      #   is claimed only while this one is non-empty, by a bridge that commits
      #   first, so a listener here always reads a committed buffer.
      #   @return [Listeners]
      listener :on_enter do |claimed|
        claimed ? editor.on_enter << @enter_bridge : editor.on_enter.remove(@enter_bridge)
      end

      # Commits on ENTER, and leaves the key unconsumed so it keeps bubbling.
      #
      # The editor declines ENTER whenever {#on_enter} is empty, so the key
      # reaches this field instead — and it must be committed on the way past,
      # or the form default button it is bubbling towards acts on an
      # uncommitted buffer.
      # @param key [String]
      # @return [Boolean] whatever `super` returns — committing never consumes
      #   the key.
      def handle_key?(key)
        commit_and_notify if key == Keys::ENTER
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
        commit_and_notify if was && !active?
      end

      # @return [void]
      def handle_focus
        super
        # The editor is what actually edits, so it takes the focus this field was
        # given — the field itself has no keys of its own.
        screen.focused = editor if editor.focusable?
      end

      protected

      # @return [AbstractStringField] the wrapped editor.
      attr_reader :editor

      # Called on a commit gesture — the field leaving the focus chain, or
      # ENTER; no-op by default. This is the commit point a canonicalizing
      # field rewrites its buffer from.
      # @return [void]
      def commit = nil

      # Whether an edit of the buffer fires {HasValue#on_value_change} as it
      # happens. `true` here, which is right wherever every buffer state is a
      # value the user might mean: an {IntegerField} passing through `4` on the
      # way to `42` really does hold 4 for that keystroke. A field whose
      # grammar is **not prefix-closed** answers `false` and lets the notice
      # settle onto the commit gestures instead ({DateField}, `D_date_field`).
      #
      # Only the *push* settles: {HasValue#value} stays a live parse of the
      # buffer either way. And overriding this is half the job — {#commit} is
      # covered here, but the field must fire from its own `set_value` too, or a
      # programmatic write and an Up/Down step go unannounced until the next
      # commit.
      # @return [Boolean]
      def notify_on_edit? = true

      # Called whenever the editor's buffer changes, however the characters
      # arrived — a typed key, a paste, or a {#set_value} of this field's own. It
      # is named for the *editor*, not for the user, because those last two are
      # not input. No-op by default; override it to drop state that describes
      # the *previous* buffer, as a field latching whether its input has settled
      # must ({HasBadInput}).
      # @return [void]
      def handle_editor_change; end

      # Places the editor across the whole rect; override to reserve cells for a
      # face of your own.
      # @return [void]
      def relayout = (editor.rect = local_rect)

      private

      # Every commit gesture runs through here, so a field holding its notice
      # ({#notify_on_edit?}) announces from one place rather than three; the
      # diff guard makes the call free for a field that fired on the way in.
      # @return [void]
      def commit_and_notify
        commit
        fire_if_changed(from_user: true)
      end

      # Re-emits {HasValue#on_value_change}, but only when {#value} differs from
      # the last one fired — so a buffer edit that leaves the value alone
      # (`"7"`→`"07"`) stays silent.
      # @param from_user [Boolean] what the write that moved the buffer declared.
      # @return [void]
      def fire_if_changed(from_user:)
        v = value
        return if v == @last_value

        @last_value = v
        on_value_change.fire(HasValue::ValueChangeEvent.new(source: self, value: v, from_user:))
      end
    end
  end
end
