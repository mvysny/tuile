# frozen_string_literal: true

module Tuile
  # A UI component which is positioned on the screen and draws characters into
  # its bounding rectangle (in {#repaint}).
  #
  # Painting is gated by attachment: a detached component (one whose {#root}
  # isn't {Screen#pane}) is never enqueued for repaint via {#invalidate}, and
  # any stale invalidation entries are filtered out at drain time. Subclasses
  # can paint freely in {#repaint} without re-asserting attachment.
  class Component
    # The methods that *define* the tree, and so may never be overridden.
    # {#attached?} walks the parent chain while every subtree walk uses
    # {#children}, so a subclass reimplementing either makes the two disagree:
    # a component that is attached but never painted, or a lifecycle hook fired
    # for the wrong set. Enforced by {.verify_final!}.
    # @return [Array<Symbol>]
    FINAL_METHODS = %i[children parent parent= add_child remove_child detach_child].freeze

    @final_verified = {}

    # Raises unless `klass` inherits every {FINAL_METHODS} entry from
    # {Component}. Ruby has no `final`, so this is it; resolving each method and
    # comparing its `owner` catches every route in — `def`, `define_method`, an
    # included module, a `prepend`. Called once per class, from {#initialize}.
    # @param klass [Class] the class being instantiated.
    # @raise [Error] if any final method has been overridden.
    # @return [void]
    def self.verify_final!(klass)
      return if @final_verified.key?(klass)

      overridden = FINAL_METHODS.reject { klass.instance_method(_1).owner == Component }
      unless overridden.empty?
        raise Error, "#{klass} overrides #{overridden.join(", ")}, which are final on Component. " \
                     "The tree is the framework's single source of truth — #attached? walks the " \
                     "parent chain while subtree walks use #children, so an override desyncs them " \
                     "silently. Reparent through add_child / remove_child / detach_child; for a " \
                     "swappable region, hold a Component::Slot."
      end

      @final_verified[klass] = true
    end

    def initialize
      Component.verify_final!(self.class)
      @rect = Rect.new(0, 0, 0, 0)
      @active = false
      @on_theme_changed = nil
      @bg_color = nil
      @children = []
    end

    # @return [Rect] the rectangle the component occupies on screen.
    attr_reader :rect

    # The three readers below report the geometry a parent *assigned*, as
    # shorthand for the matching {#rect} field. They are reports, not requests:
    # no container consults them when dividing space, and there is deliberately
    # no writer — layout is top-down (`DECISIONS.md` `D_box_layouts`), so a
    # component says how big it *is*, never how big it wants to be.

    # @return [Size] `rect.size`.
    def size = rect.size

    # @return [Integer] `rect.width`.
    def width = rect.width

    # @return [Integer] `rect.height`.
    def height = rect.height

    # The size of the region this component paints, or `nil` (the default) to
    # declare nothing — in which case the whole {#rect} is treated as fair game
    # and the default {#repaint} blanks all of it. Override it when you paint
    # less: a one-row {Component::Checkbox} handed a tall column, or a
    # {Component::Select} used as a {Component::Popup}'s content and assigned the
    # whole inner box.
    #
    # It always sits at {#rect}'s top-left — which is why this is a {Size} and
    # not a {Rect}: an offset extent is not merely unsupported, it is
    # unrepresentable. Use {#extent_rect} where coordinates are wanted.
    #
    # **`nil` is not the same as `rect.size`.** `nil` says "I have not declared
    # what I paint, so clear everything before I do", which is what a
    # {Component::Label} with short text needs. A declared extent — even one that
    # happens to equal the rect, as a one-row {Component::Select} in a one-row
    # rect does — says "I paint this in full, don't blank it", which is what
    # keeps the default {#repaint} from dirtying cells it is about to redraw
    # (`D_progress_bar`). The base cannot tell those apart from the value alone;
    # that is what the `nil` carries.
    #
    # It flows **downward only**: no container consults it when dividing space,
    # so {#rect} still means exactly what the parent assigned (`D_extent`). Three
    # things read it, all of them this component or the framework painting it:
    # {#clear_outside_extent} blanks the dead tail, {#handle_mouse} hit-tests
    # against it so a click on that tail doesn't activate the widget, and a
    # dropdown anchors under it rather than under unused space.
    #
    # **An override promises to paint the extent in full**, so `super` in
    # {#repaint} blanks only what is outside it. The arithmetic is each widget's
    # own — caption width, painted strip, one row — and must not vary with
    # {#bg_color} (`D_boolean_fields`).
    # @return [Size, nil]
    def extent = nil

    # {#extent} placed at {#rect}'s top-left, for the consumers that need
    # coordinates: `extent_rect.contains?(event.point)` in a {#handle_mouse}, and
    # the anchor a dropdown hangs from. Total — an undeclared {#extent} yields
    # the whole {#rect}, so a generic caller never sees `nil`.
    # @return [Rect]
    def extent_rect
      e = extent
      e.nil? ? rect : Rect.new(rect.left, rect.top, e.width, e.height)
    end

    # Sets new position of the component. This is the absolute component
    # positioning on screen, not a relative positioning relative to component's
    # {#parent}.
    #
    # The component must not stick outside of {#parent}'s rect.
    #
    # The component is invalidated and will paint over the new rectangle. It is
    # parent's job to paint over the old component position.
    # @param new_rect [Rect] new position. Does nothing if the new rectangle is
    #   the same as the old one.
    def rect=(new_rect)
      raise TypeError, "expected Rect, got #{new_rect.inspect}" unless new_rect.is_a? Rect
      return if @rect == new_rect

      prev_width = @rect.width
      @rect = new_rect
      on_width_changed if prev_width != new_rect.width
      invalidate
    end

    # @return [Screen] the screen which owns this component.
    def screen = Screen.instance

    # Focuses this component. Equivalent to `screen.focused = self`.
    # @return [void]
    def focus
      screen.focused = self
    end

    # @return [Color, Theme::Ref, nil] this component's own background — the
    #   value as set, so a {Theme::Ref} comes back unresolved; `nil` when unset,
    #   in which case it inherits from the parent (see {#effective_bg_color}),
    #   ultimately the terminal default. {#effective_bg_color} is the resolved
    #   {Color} to paint.
    attr_reader :bg_color

    # Tints this component and every descendant that doesn't set its own
    # background (they re-resolve via {#effective_bg_color}) — set it once on a
    # container / {Component::Popup} to tint a whole subtree. Invalidates the
    # subtree so it repaints.
    #
    # A {Theme::Ref} is re-resolved against the theme each paint, so it tracks
    # light/dark flips with no {#on_theme_changed} hook; a {Color} is fixed:
    #
    #   panel.bg_color = Theme.ref(:panel_bg)   # theme-tracked
    #   panel.bg_color = Color::GREY27          # fixed
    #
    # @param color [Color, Theme::Ref, Symbol, Integer, Array<Integer>, nil] a
    #   {Theme::Ref}, else a color coerced via {Color.coerce}; `nil` unsets
    #   (inherit from the parent).
    # @raise [KeyError] when a {Theme::Ref} names an absent custom token —
    #   validated eagerly at assignment, not deferred to paint.
    # @return [void]
    def bg_color=(color)
      color = Color.coerce(color) unless color.is_a?(Theme::Ref)
      return if @bg_color == color

      color.resolve(screen.theme) if color.is_a?(Theme::Ref) # fail fast on a bad token
      @bg_color = color
      on_tree { |c| screen.invalidate(c) } if attached?
    end

    # @return [Color, nil] the background actually painted: this component's own
    #   {#bg_color} if set (a {Theme::Ref} resolved against the current theme),
    #   else the nearest ancestor's, else `nil` (terminal default). Resolved at
    #   paint time — never cached, so the subtree tracks both an ancestor's
    #   {#bg_color=} and a {Screen#theme=} on its next repaint.
    def effective_bg_color
      own = @bg_color
      own = own.resolve(screen.theme) if own.is_a?(Theme::Ref)
      own || parent&.effective_bg_color
    end

    # Repaints the component. The default does the bookkeeping most components
    # need: it clears the background — unless the direct children already tile
    # {#rect}, in which case there is no gap to wipe and blanking cells they are
    # about to repaint would only make them dirty — and then re-invalidates
    # those children so they paint over the cleared area. That is what makes
    # mixed-width form layouts safe.
    #
    # Call `super` from your own `repaint` to inherit this. Skip it only if you
    # paint the whole {#rect} yourself ({Window}'s border, {Component::List}'s
    # row-by-row paint). Never draw outside {#rect}. Only called when attached.
    #
    # **A widget that paints less than its rect declares an {#extent} rather than
    # skipping `super`.** The clear then covers only what is outside it, so the
    # cells it is about to repaint are not blanked first — blanking them would
    # mark them dirty and make {Buffer#flush} re-emit them (`D_progress_bar`).
    #
    # **The children are re-invalidated whether or not they tile.** A container
    # that paints nothing of its own can only redraw its area *through* them, so
    # a tiling container that skipped this would be a dead end in the cascade: an
    # ancestor's `clear_background` wipes the whole ancestor rect — siblings and
    # grandchildren included — and re-invalidates only its *direct* children, so
    # the notice has to keep travelling down or the cleared cells are never
    # repainted. Cheap by construction: repainting the same glyphs leaves
    # {Buffer::Cell} unchanged, so nothing extra reaches the wire.
    # @return [void]
    def repaint
      return if rect.empty?

      clear_outside_extent unless children.any? && children_tile_rect?
      children.each { |c| screen.invalidate(c) }
    end

    # Called when a key is pressed; override to act on keys you care about (the
    # default reports every key unhandled). A component only receives keys while
    # it's on the focus chain — or when app code hands it one directly — so act
    # on the key alone and never gate on your own {#active?} state. See book ch5
    # for how a keystroke is routed to reach here.
    # @param _key [String] a key.
    # @return [Boolean] true if the key was handled, false if not.
    def handle_key(_key)
      false
    end

    # Called when text is pasted while this component is on the focus chain;
    # override to accept it (the default reports every paste unhandled, and
    # unhandled text is dropped). Arrives whole and `\n`-normalized, so
    # `text.lines.size` is the paste's line count and a single mutation can
    # absorb it:
    #
    #   def handle_paste(text)
    #     self.caption = "[Pasted #{text.lines.size} lines]"
    #     true
    #   end
    #
    # Reaching here means the terminal said "this came from the clipboard" —
    # {Component::AbstractStringField} inserts it at the caret, which is why a
    # subclass that rebinds ENTER to submit needs no paste handling of its own
    # to stop firing once per pasted line.
    # @param _text [String] the pasted text.
    # @return [Boolean] true if the paste was consumed.
    def handle_paste(_text)
      false
    end

    # Focuses this component when left-clicked (if {#focusable?}), then hands the
    # event down to every child whose {#rect} contains the point — which is how a
    # click descends the tiled tree to a leaf.
    #
    # A widget that resolves clicks *inside* its own rect — mapping a point to a
    # row, or toggling an overlay — overrides this and does not call `super`.
    # Such an override hit-tests {#extent_rect} rather than {#rect}, so a click
    # on the tail it doesn't paint never activates it.
    # @param event [MouseEvent]
    # @return [void]
    def handle_mouse(event)
      screen.focused = self unless event.button != :left || active? || !focusable?
      # Snapshot: a handler may add or remove siblings (a click that swaps a
      # slot's occupant), and `each` over a mutating array skips an entry.
      children.dup.each { |c| c.handle_mouse(event) if c.rect.contains?(event.point) }
    end

    # @return [Boolean] true if the component is on the active chain — i.e. it
    #   is the focused component or an ancestor of it. Set by {Screen#focused=}.
    def active? = @active

    # @param active [Boolean] true if active. Set by {Screen#focused=} as it
    #   marks the focus chain (root → focused); not meant to be called directly.
    # @return [void]
    def active=(active)
      active = active ? true : false
      return unless @active != active

      @active = active
      invalidate
    end

    # Whether this component is a valid focus target. `false` by default —
    # passive components like {Label} are decoration and don't accept focus.
    # The flag gates click-to-focus and the container focus-cascade. Independent
    # from {#active?}: every component carries the active flag, but only
    # focusable ones can become a focus target that puts themselves and their
    # ancestors on the active chain. Focusable is broader than {#tab_stop?} —
    # a {Window} is focusable (a click on chrome lands focus) but not a tab stop.
    # @return [Boolean] true if this component can be focused.
    def focusable? = false

    # Whether this component participates in Tab / Shift+Tab focus cycling.
    # `false` by default. Only true on components that accept direct user
    # input (e.g. {TextField}, {List}, {Component::Button}). Implies
    # {#focusable?} — Screen will skip non-focusable tab stops, but in
    # practice every override should keep the two consistent.
    # @return [Boolean] true if Tab / Shift+Tab should land on this component.
    def tab_stop? = false

    # @return [Component, nil] the parent component or nil if the component has
    #   no parent.
    attr_reader :parent

    # @return [Integer] the distance from the root component; 0 if {#parent}
    #   is nil.
    def depth = parent.nil? ? 0 : parent.depth + 1

    # @return [Component] the root component of this component hierarchy.
    def root = parent.nil? ? self : parent.root

    # Child components in paint order (siblings left to right, earlier ones
    # painted under later ones), maintained by {#add_child} / {#remove_child}.
    #
    # Not meant to be overridden: a container that computed this from its own
    # slots could disagree with the parent pointers, and {#attached?} walks the
    # chain while subtree walks use this list. Named slots are readers *over*
    # the array (`Window#footer`), never a second copy of it.
    # @return [Array<Component>] child components. Must not be mutated by
    #   callers! May be empty.
    attr_reader :children

    # Calls block for this component and for every descendant component.
    # @yield [component]
    # @yieldparam component [Component]
    # @yieldreturn [void]
    # @return [void]
    def on_tree(&block)
      block.call(self)
      children.each { _1.on_tree(&block) }
    end

    # Called when the component receives focus.
    # @return [void]
    def on_focus; end

    # Optional zero-arg listener fired by the base {#on_theme_changed} — the
    # composition-style alternative to overriding the method, for apps that
    # assemble stock components rather than subclass:
    #
    #   label.on_theme_changed = -> { label.text = render_status_line }
    #
    # @return [Proc, nil]
    attr_writer :on_theme_changed

    # Whether this component's tree is mounted on a UI, {ScreenPane} being the
    # root of every displayed tree.
    #
    # A property of the parent chain alone — no {Screen} is consulted, so
    # assembling a tree needs no screen in the process at all:
    #
    #   layout = Component::Layout::Absolute.new
    #   layout.add(label)      # legal with no Screen; neither is attached yet
    #   screen.content = layout # now both are
    #
    # @return [Boolean] true if {#root} is a {ScreenPane}.
    def attached? = root.is_a?(ScreenPane)

    # Called by container components after `child` has been detached from
    # `self.children` (its `parent` is already nil and it is no longer in the
    # children list). Default behavior repairs dangling focus: if the focused
    # component lived inside the removed subtree, focus shifts to `self` so the
    # cursor doesn't dangle on a detached component. No-op if `self` is not
    # attached to the screen — focus state in a detached subtree is moot.
    # @param child [Component] the just-detached child.
    # @return [void]
    def on_child_removed(child)
      return unless attached?

      f = screen.focused
      return if f.nil?

      cursor = f
      until cursor.nil?
        if cursor == child
          screen.focused = self
          return
        end
        cursor = cursor.parent
      end
    end

    # Where the hardware terminal cursor should sit when this component is the
    # cursor owner. Returns `nil` to indicate the cursor should be hidden. The
    # {Screen} positions the hardware cursor after each repaint cycle by
    # consulting the {Screen#focused} component only.
    # @return [Point, nil] absolute screen coordinates, or nil to hide.
    def cursor_position = nil

    protected

    # Adopts `child`: places it in {#children} and wires its parent pointer.
    #
    #   add_child(content, at: 0)   # the tiled layer, painted beneath …
    #   add_child(@footer)          # … and chrome appended, painted over it
    #
    # @param child [Component] must not already have a parent.
    # @param at [Integer, nil] index to insert at; appends when nil.
    # @raise [TypeError] if `child` is not a {Component}.
    # @raise [ArgumentError] if `child` already has a parent.
    # @return [void]
    def add_child(child, at: nil)
      raise TypeError, "expected Component, got #{child.inspect}" unless child.is_a? Component
      raise ArgumentError, "#{child} already has a parent #{child.parent}" unless child.parent.nil?

      at.nil? ? @children.push(child) : @children.insert(at, child)
      child.parent = self
    end

    # Drops `child` and notifies {#on_child_removed}.
    # @param child [Component]
    # @raise [ArgumentError] if `child` is not a child of this component.
    # @return [void]
    def remove_child(child)
      detach_child(child)
      on_child_removed(child)
    end

    # Drops `child` *without* notifying — for a container swapping a named slot,
    # which owes the {#on_child_removed} call once the new occupant is wired:
    #
    #   detach_child(old)
    #   @content = new
    #   add_child(new, at: 0)
    #   on_child_removed(old)   # focus repair cascades into the *new* content
    #
    # The child leaves {#children} before its pointer is cleared, so nothing
    # observes a child whose parent has disowned it while still listing it.
    # @param child [Component]
    # @raise [ArgumentError] if `child` is not a child of this component.
    # @return [void]
    def detach_child(child)
      raise ArgumentError, "#{child} is not a child of #{self}" unless @children.include?(child)

      @children.delete(child)
      child.parent = nil
    end

    # Called once this component's tree has been mounted on a {ScreenPane},
    # i.e. when {#attached?} flips to true — the place to acquire whatever is
    # supposed to live for exactly as long as the component is on screen:
    #
    #   def on_attached
    #     @ticker = screen.event_queue.tick_fps(10) { advance }
    #   end
    #
    #   def on_detached
    #     @ticker&.cancel
    #     @ticker = nil
    #   end
    #
    # `on_attached` starts what `on_detached` stops; both must be cheap and
    # idempotent, since a component moved between parents is genuinely detached
    # in between and gets both, in that order. Whatever you acquire here you
    # must release in {#on_detached} — nothing else will. Not a destructor:
    # process teardown does *not* fire {#on_detached}.
    #
    # {#invalidate} needs no guard: {#attached?} is already true here (and
    # already false in {#on_detached}, where it no-ops). Do not read {#rect} —
    # a parent assigns it *after* wiring, so it is still stale. Runs on the
    # thread that owns the UI.
    # @return [void]
    def on_attached; end

    # Mirror of {#on_attached}, called once the tree has been unmounted — see
    # there for the contract. Two things are still mid-flight when it runs, both
    # deliberate: {Screen#focused} may still point into this subtree (repair
    # happens after), and the ex-parent's own bookkeeping may not be finished.
    # So release resources here and don't inspect the tree around you.
    # @return [void]
    def on_detached; end

    # Rewires the parent pointer and, when that changes whether the component is
    # {#attached?}, fires {#on_attached} / {#on_detached} across the whole
    # subtree. The sole firing site: `add_child` / `detach_child` are the only
    # callers, and they update {#children} *before* calling this, so a hook sees
    # a tree whose list and pointers already agree.
    #
    # Reparenting inside an already-attached tree fires nothing (attachedness
    # doesn't change), and neither does building a detached tree.
    # @param new_parent [Component, nil]
    # @return [void]
    def parent=(new_parent)
      was_attached = attached?
      @parent = new_parent
      return if was_attached == attached?

      fire_lifecycle(attached?)
    end

    # Walks self-then-children calling one lifecycle hook, delivering at most one
    # call per component per transition however the hooks mutate the tree. Two
    # guards, because a hook runs *before* its own children are visited:
    #
    # - the **snapshot** covers a child a hook *adds* — it isn't in `kids`, and
    #   fires exactly once through its own `parent=`;
    # - the **state re-check** covers a child a hook *removes*. Matching on
    #   current attachedness rather than on `parent.equal?(self)`: a child pulled
    #   out during a detach walk is *already* detached, so its own `parent=` saw
    #   no transition and stayed silent — a parentage check would skip it too and
    #   it would never hear `on_detached` at all. The reverse case (pulled out
    #   during an *attach* walk) gets `on_detached` from its own `parent=` and no
    #   `on_attached`, which is why the hooks are required to be idempotent: an
    #   unpaired detach releases nothing, whereas firing `on_attached` at a
    #   component that is no longer attached would start a ticker nothing stops.
    #
    # @param attached [Boolean] true to fire {#on_attached}, false for {#on_detached}.
    # @return [void]
    def fire_lifecycle(attached)
      kids = children.dup
      attached ? on_attached : on_detached
      kids.each { _1.fire_lifecycle(attached) if _1.attached? == attached }
    end

    # Called whenever the component width changes. Does nothing by default.
    # @return [void]
    def on_width_changed; end

    # Called on every attached component (pre-order, popups included) when
    # {Screen#theme} changes — at {Screen#theme=} / {Screen#theme_def=} and on
    # OS appearance flips. The hook exists for app *content* whose colors were
    # baked in from the old theme (a {Label#text} / {List#lines=} {StyledString}
    # styled with `theme[:accent]`); rebuild it here by re-running the code that
    # rendered it. See book ch6 for why built-in accents need no such handling.
    #
    # Runs on the UI thread with {Screen#theme} already updated, so mutating
    # content (`text=`, `lines=`, …) is safe. Do not assign {Screen#theme=}
    # here. Subclasses overriding this must call `super` so an assigned
    # {#on_theme_changed=} listener keeps firing.
    #
    # Plumbing an app overrides and never calls, hence protected — and
    # {Screen}, not being a {Component}, fans it out through `__send__`, so an
    # override is free to declare any visibility (`D_hook_visibility`).
    # @return [void]
    def on_theme_changed
      @on_theme_changed&.call
    end

    # Invalidates the component: {Screen} records this component as
    # needs-repaint and once all events are processed, will call {#repaint}.
    #
    # No-op when the component is not {#attached?} — a detached component has
    # no place on the screen to paint to, so {Screen} must never end up
    # repainting it. Callers don't need to guard their own `invalidate` calls;
    # mutating a detached component (e.g. setting `lines=` on a {List} sitting
    # inside a closed {Component::Popup}) is silent.
    # @return [void]
    def invalidate
      return unless attached?

      screen.invalidate(self)
    end

    # Whether direct children fully tile {#rect}. Used by the default
    # {#repaint} to decide whether the framework needs to wipe gaps.
    #
    # Approximated by area: sum of (non-empty) child areas vs the parent's
    # area. Cheap, and correct as long as siblings don't overlap each other
    # — which Tuile already requires (no clipping in the tiled tree).
    # Children with empty rects contribute zero, since they paint nothing.
    # @return [Boolean]
    def children_tile_rect?
      total = children.sum { |c| c.rect.empty? ? 0 : c.rect.width * c.rect.height }
      total >= rect.width * rect.height
    end

    # Blanks the part of {#rect} outside {#extent} — the dead tail a widget that
    # paints less than it was given must not leave stale. Up to two regions,
    # since a narrowed extent leaves an L: the columns right of it, and the rows
    # below it. A `nil` extent declares nothing, so the whole rect is blanked.
    # Called by the default {#repaint}; a self-painter that skips `super` calls
    # it directly.
    # @return [void]
    def clear_outside_extent
      e = extent
      return clear_background if e.nil? # nothing declared: all of it is fair game

      right = Rect.new(rect.left + e.width, rect.top, rect.width - e.width, e.height)
      below = Rect.new(rect.left, rect.top + e.height, rect.width, rect.height - e.height)
      clear_background(right) unless right.empty?
      clear_background(below) unless below.empty?
    end

    # Clears the background: fills every cell with a blank in the
    # {#effective_bg_color} (the terminal default when none is inherited).
    #
    # A component that paints part of its {#rect} itself passes just the part it
    # *doesn't* — blanking a cell it is about to overwrite anyway makes that cell
    # dirty, and {Buffer#flush} then re-emits it even though nothing visibly
    # changed.
    # @param area [Rect] the region to blank; defaults to the whole {#rect}.
    # @return [void]
    def clear_background(area = rect)
      bg = effective_bg_color
      screen.buffer.fill(area, bg ? StyledString::Style.new(bg:) : StyledString::Style::DEFAULT)
    end

    # {Buffer#set_text} wrapper that fills {#effective_bg_color} behind any span
    # with no bg of its own (via {StyledString#under_bg}), so an inherited
    # {#bg_color} shows through the content a component paints. A no-op layer
    # when nothing is inherited. Self-painters (those skipping the {#repaint}
    # auto-clear) paint through this instead of {Screen#buffer} directly.
    # @param x [Integer] starting column.
    # @param y [Integer] row.
    # @param styled [StyledString]
    # @return [void]
    def draw_text(x, y, styled)
      screen.buffer.set_text(x, y, styled.under_bg(effective_bg_color))
    end

    # {#draw_text}'s single-grapheme counterpart: writes `grapheme` at `(x, y)`,
    # filling {#effective_bg_color} when `style` carries no bg of its own.
    # @param x [Integer] column.
    # @param y [Integer] row.
    # @param grapheme [String] one grapheme cluster.
    # @param style [StyledString::Style]
    # @return [void]
    def draw_char(x, y, grapheme, style = StyledString::Style::DEFAULT)
      bg = effective_bg_color
      style = style.merge(bg:) if bg && style.bg.nil?
      screen.buffer.set_char(x, y, grapheme, style)
    end
  end
end
