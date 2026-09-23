# frozen_string_literal: true

module Tuile
  # A UI component which is positioned on the screen and draws characters into
  # its bounding rectangle (in {#repaint}).
  #
  # Painting is gated by attachment: a detached component (one whose {#root}
  # isn't {Screen#pane}) is never enqueued for repaint via {#invalidate}, and
  # any stale invalidation entries are filtered out at drain time. Subclasses
  # can paint freely in {#repaint} without re-asserting attachment.
  #
  # == Handlers and listener slots
  #
  # Two families — `handle_` is the override point, `on_` the listener slot:
  #
  #   class Trimmed < Component::TextField
  #     def handle_blur                  # handle_ — the override point
  #       super
  #       self.value = text.strip
  #     end
  #   end
  #
  #   label.on_theme_changed { … }        # on_… — the listener slot, a {Listeners}
  #
  # A slot holds *many* listeners and has no setter: register with the reader,
  # remove with {Listeners#remove}, and nothing you add can displace what the
  # widget or another app wired there.
  #
  # **What a handler returns is per hook**, declared in its own rdoc. Only the
  # ones a dispatcher routes answer at all — {#handle_key?},
  # {#handle_text_input_key?}, `MenuBar#handle_mnemonic?` — where `true` means "I
  # took this, stop bubbling". The rest, {#handle_paste} included, return `void`.
  #
  # An override calls `super`, even where the base body is empty: that is what
  # lets a hook grow an `on_foo` slot without breaking you. The one carve-out is
  # {#handle_child_removed}, whose base does real work and whose overrides
  # replace it. `D_handler_naming` carries the argument.
  class Component
    extend Final
    extend Listeners::Declare

    # Each method's own rdoc says what an override would break; `D_final_tree`
    # carries the full argument.
    final :children, :parent, :parent=, :add_child, :remove_child, :detach_child,
          :bg

    def initialize
      Component.verify_final!(self.class)
      @rect = Rect.new(0, 0, 0, 0)
      @visible = true
      @active = false
      @bg = ComponentBackground.new(self)
      @children = []
      @id = nil
      @layout_dirty = false
    end

    # A tag for finding this component again — nothing paints it, and the
    # framework never reads it:
    #
    #   field.id = :name
    #   Testing.get(id: :name).value = "Zaphod"
    #
    # **Nothing enforces uniqueness**, here or anywhere in production; two
    # components may carry the same id, and only {Testing.get} — which raises
    # on an ambiguous match — will ever say so.
    # @return [Symbol, nil]
    attr_reader :id

    # A `String` is refused rather than coerced: `id = "name"` would never
    # match a `get(id: :name)`, silently.
    # @param new_id [Symbol, nil]
    # @raise [TypeError] unless `new_id` is a Symbol or nil.
    # @return [void]
    def id=(new_id)
      raise TypeError, "expected Symbol or nil, got #{new_id.inspect}" unless new_id.nil? || new_id.is_a?(Symbol)

      @id = new_id
    end

    # The rectangle the component occupies **inside its parent**: `(0, 0)` is
    # the parent's top-left, not the screen's. {#absolute_rect} is where that
    # lands on screen, and {#local_rect} is this same rectangle with the
    # position taken out.
    #
    # **Layout is deferred, so a rect read in the same turn that dirtied it is
    # the *previous* pass's** — a plausible rectangle, not zeros.
    # {#flush_layout} brings it up to date (`D_deferred_layout`),
    # {#rect_stale?} answers whether it is one, and {Tuile.strict_layout} makes
    # every such read say so.
    # @return [Rect]
    attr_reader :rect

    # The three readers below report the geometry a parent *assigned*, as
    # shorthand for the matching {#rect} field. They are reports, not requests:
    # no container consults them when dividing space, and there is deliberately
    # no writer — layout is top-down (`design/decisions.md` `D_box_layouts`), so a
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
    # unrepresentable. Use {#local_extent_rect} or {#absolute_extent_rect} where
    # coordinates are wanted — there is no parent-space form, because nothing
    # asks the question in that space.
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
    # {#clear_outside_extent} blanks the dead tail, {Mouse::Router} hit-tests
    # against {#local_extent_rect} so a click on that tail doesn't activate the
    # widget, and a dropdown anchors under {#absolute_extent_rect} rather than
    # under unused space.
    #
    # **An override promises to paint the extent in full**, so `super` in
    # {#repaint} blanks only what is outside it. The arithmetic is each widget's
    # own — caption width, painted strip, one row — and must not vary with
    # {#bg_color} (`D_boolean_fields`).
    # @return [Size, nil]
    def extent = nil

    # {#rect} with the position taken out: the same size at `(0, 0)`.
    #
    # **Two things live in these coordinates**, and that is the whole point of
    # them being one space: what this component *paints* ({Screen#canvas_for}
    # puts the canvas here), and what its children's {#rect}s are measured in.
    # So a container divides `local_rect` among its children and blanks its own
    # gaps in the very same numbers:
    #
    #   private def relayout
    #     half = width / 2                       # no `rect.left +` anywhere:
    #     left.rect  = Rect.new(0, 0, half, height)
    #     right.rect = Rect.new(half, 0, width - half, height)
    #   end
    #
    # @return [Rect]
    def local_rect = Rect.new(0, 0, rect.width, rect.height)

    # {#extent} at `(0, 0)`, {#local_rect}'s counterpart — what
    # {#clear_inside_extent} blanks and what {Mouse::Router} hit-tests. Total:
    # an undeclared {#extent} yields {#local_rect}, so a generic caller never
    # sees `nil`.
    # @return [Rect]
    def local_extent_rect
      e = extent
      e.nil? ? local_rect : Rect.new(0, 0, e.width, e.height)
    end

    # {#rect} in **screen** coordinates — every ancestor's offset summed in.
    # The form the three consumers outside this component's own frame need: the
    # {Canvas#origin} {Screen#canvas_for} builds, an overlay's anchor (an
    # overlay hangs off {ScreenPane}, so it shares no offset with its driver),
    # and a spec clicking a component by where it sits.
    #
    # Derived on every call and never cached — a parent may move this subtree
    # between two reads, and nothing announces it (`D_relative_rect`).
    # @return [Rect]
    def absolute_rect = rect.at(to_screen(Point::ZERO))

    # {#local_extent_rect} in screen coordinates, {#absolute_rect}'s
    # counterpart — what a dropdown anchors against.
    # @return [Rect]
    def absolute_extent_rect = local_extent_rect.at(to_screen(Point::ZERO))

    # Converts a point in *this component's own* coordinates — the ones it
    # paints in, the ones a {Mouse::Event} reaches it in — to screen
    # coordinates, by walking up and adding each ancestor's offset.
    #
    #   # a strip anchoring a panel under one of its own segments
    #   Rect.new(0, 0, width, 1).at(to_screen(Point.new(column, 0)))
    #
    # Iterative and summing into two locals rather than recursing through a
    # {Point} per level: this runs once per component per repaint, from
    # {Screen#canvas_for}.
    # @param point [Point] in this component's coordinates.
    # @return [Point] in screen coordinates.
    def to_screen(point)
      x = point.x
      y = point.y
      node = self
      until node.nil?
        x += node.rect.left
        y += node.rect.top
        node = node.parent
      end
      Point.new(x, y)
    end

    # {#to_screen}'s inverse: a screen point in this component's own
    # coordinates. The result may be negative or past {#size} — a point outside
    # the component converts perfectly well, which is what a grabbed component's
    # {Mouse::DragEvent} relies on.
    # @param point [Point] in screen coordinates.
    # @return [Point] in this component's coordinates.
    def to_local(point)
      x = point.x
      y = point.y
      node = self
      until node.nil?
        x -= node.rect.left
        y -= node.rect.top
        node = node.parent
      end
      Point.new(x, y)
    end

    # Places the component **inside its parent**: `(0, 0)` is the parent's
    # top-left, so a container divides its own {#local_rect} and never adds its
    # own position in. {#absolute_rect} is where the result lands on screen.
    #
    # A component that sticks outside its parent's {#local_rect}, or paints
    # outside this rectangle, is cut to it — {Screen#canvas_for} bounds every
    # component by its own rect and every ancestor's (`D_clip`). Overrunning is
    # still a bug; it now shows as truncation rather than as a corrupt neighbour.
    #
    # The component is invalidated and will paint over the new rectangle, and
    # so is its parent, which owns the cells the old position vacated.
    #
    # **The children do not move yet**: this only marks a {#relayout}, so a
    # child's rect read back in the same turn is still the previous pass's —
    # {#flush_layout} first.
    #
    # **Only the parent's {#relayout} may call this**, and it raises from
    # anywhere else, a component with no parent included. To move a child,
    # change what its parent places it by — {Layout::Absolute#constrain},
    # {Layout::Box#constrain}, {Component::Overlay#placement=} — and to size a
    # tree that has no screen, hold it in a {Layout::Absolute}:
    #
    #   holder = Component::Layout::Absolute.new
    #   holder.add(tree, Rect.new(0, 0, 40, 10))
    #   holder.flush_layout
    #
    # A subclass reacts to a new rect in {#handle_rect_changed}; it cannot
    # override this, because a `protected` override is callable only from its
    # own class, and the parent calling it is not one.
    # @param new_rect [Rect] new position. Does nothing if the new rectangle is
    #   the same as the old one.
    # @raise [Tuile::Error] unless the parent's {#relayout} is running.
    def rect=(new_rect)
      raise TypeError, "expected Rect, got #{new_rect.inspect}" unless new_rect.is_a? Rect

      LayoutPass.check(self)
      LayoutPass.note_placement
      return if @rect == new_rect

      old_rect = @rect
      @rect = new_rect
      handle_rect_changed(old_rect)
      invalidate
      # Nothing else blanks the cells the old rect vacated — the same reason
      # {#visible=} invalidates the parent.
      parent&.invalidate
      invalidate_layout
    end
    protected :rect=

    # Runs every {#relayout} this component's *tree* owes, so its rects are
    # current — the force-now that makes a detached tree measurable:
    #
    #   layout = Component::Layout::Vertical.new   # no Screen in the process
    #   layout.add(label, Fixed[1])
    #   layout.rect = Rect.new(0, 0, 20, 10)
    #   layout.flush_layout
    #   label.rect                                 # => Rect(0, 0, 20, 1)
    #
    # Attached, {Screen#dispatch} already flushes after every event, so ask for
    # this by hand only to read a rect in the *same* turn that dirtied it —
    # what Swing spells `validate()` and Tk `update idletasks`.
    #
    # **Overwhelmingly that means a spec**: an app mutates and lets the settle
    # run, so a `flush_layout` in app code is usually a sign the *read* wants
    # deferring instead.
    #
    # == Implementation details
    #
    # The whole tree, never this subtree, whichever end it is asked from: a
    # pending ancestor pass would overwrite whatever a narrower one wrote.
    # Attached that is {Screen#flush_layout}; detached it is the same fixpoint
    # over pre-order passes from {#root}, so a parent lays out before the
    # children whose rects it just wrote.
    # @return [void]
    def flush_layout
      return screen.flush_layout if attached?

      loop do
        pending = []
        root.walk_tree { pending << _1 if _1.layout_dirty? }
        break if pending.empty?

        pending.each { _1.__send__(:perform_relayout) }
      end
    end

    # Whether this container owes a {#relayout} — that its *children*'s rects
    # are out of date.
    #
    # **It says nothing about this component's own {#rect}**, which no pass of
    # its own touches: the flag that makes *this* rect stale sits on the parent
    # that assigns it, and {#rect_stale?} is that question asked from here.
    # Survives detaching, so {#handle_attached} can hand the mark to the {Screen}.
    # @return [Boolean]
    def layout_dirty? = @layout_dirty

    # Whether {#rect} is the *previous* pass's rectangle, because some ancestor
    # owes a {#relayout} and that pass reassigns every rect below it.
    #
    #   holder.constrain(pane, Rect.new(0, 0, 100, 26))
    #   pane.left.rect_stale?   # => true — `pane.left.rect` is still the old half
    #
    # {#flush_layout} makes it false; {Tuile.strict_layout} reports every read
    # taken while it is true. One walk to {#root} per call, which is why no
    # framework read consults it outside strict mode.
    # @return [Boolean]
    def rect_stale? = !stale_layout_ancestor.nil?

    # This component's own flag — **not** whether the user can see it, which
    # also depends on its ancestors: a shown field inside a hidden panel
    # answers `true`.
    # @return [Boolean]
    def visible? = @visible

    # Hides or shows the component: `false` means **as if detached — but it
    # stays in the tree**.
    #
    #   company.visible = business_customer.checked?   # a conditional form field
    #
    # Hidden, it paints nothing, takes no space in a
    # {Component::Layout::Box} (nor the `spacing` around it), and is
    # unreachable by focus, Tab, keys, the cursor, the mouse and
    # {Testing.find}. Unlike a *detached* component it keeps its {#parent},
    # {#rect}, box constraints, state and any resource it holds, and **fires no
    # lifecycle hook** — so a hidden pane may go on running a job. When you
    # want the hooks, remove it from the tree instead.
    #
    # Two contracts worth knowing before you meet them as bugs:
    #
    # - **Ancestor-inclusive.** Hiding a container hides its whole subtree
    #   whatever those components' own flags say; the flags are remembered, so
    #   showing it restores exactly the subtree that was showing before.
    # - **Focus never stays on what the user cannot see.** Hiding the subtree
    #   holding focus repairs it exactly as removing that subtree would (see
    #   {#handle_child_removed}), and does not hand it back on the way in.
    #
    # For "invisible but still occupying its space", use a
    # {Component::Slot} with no content (`D_slots`). The parent's own
    # {#relayout} may flip it — before placing any child, or it runs twice
    # ({#invalidate_layout}).
    # @param value [Boolean]
    # @raise [Tuile::Error] when the UI is locked, or always from
    #   {Component::Overlay#visible=}.
    # @return [void]
    def visible=(value)
      value = value ? true : false
      return if @visible == value

      screen.check_locked if attached?
      @visible = value
      # Both on the parent, because the child just vacated (or re-claimed) cells
      # the parent owns *and* may have changed how it divides its space. A
      # hidden component paints nothing itself, so nothing else would blank what
      # it left behind.
      parent&.invalidate
      parent&.invalidate_layout
      repair_focus_after_hiding unless value
      walk_tree { |c| screen.invalidate(c) } if attached?
    end

    # @return [Screen] the screen which owns this component.
    def screen = Screen.instance

    # Focuses this component. Equivalent to `screen.focused = self`.
    # @return [void]
    def focus
      screen.focused = self
    end

    # Asks whatever scrolls above to bring `rect` into view — "show me this",
    # made by the component that wants to be seen, never polled for by a
    # container:
    #
    #   row.scroll_to_visible                      # all of me
    #   editor.scroll_to_visible(caret_row_rect)   # this much of me
    #
    # The request climbs the parent chain re-expressed a level at a time, so
    # with nothing scrolling on the way it reaches the root and does nothing.
    # {Screen#focused=} makes the no-argument call on every focus assignment,
    # which is the whole of making Tab follow the view: a child scrolled out of
    # sight keeps its rect, its keys and its tab stop (`D_empty_ancestor`).
    #
    # A container that scrolls overrides it, and the shape is the contract:
    #
    #   def scroll_to_visible(rect = local_extent_rect)
    #     delta = ...                     # the minimum that makes rect visible
    #     move_scroll_top_row_by(delta)
    #     super(rect.moved_by(Point.new(0, -delta)))
    #   end
    #
    # **The minimum** distance, so the far edge of the viewport is the one
    # allowed to cut a child in half. And `super` takes the rect **where the
    # scroll left it**, so an outer scroller is asked about cells that exist and
    # nested scrollers settle inner-first.
    #
    # A hidden component raises, checked a level at a time as the request
    # climbs — so it fails late: a scroller below a hidden ancestor has
    # already scrolled.
    # @param rect [Rect] in *this* component's coordinates; defaults to
    #   {#local_extent_rect}, so a widget asks for what it paints.
    # @raise [Tuile::Error] when this component or an ancestor is hidden.
    # @return [void]
    def scroll_to_visible(rect = local_extent_rect)
      raise Tuile::Error, "#{self} is hidden; it cannot be scrolled into view" unless visible?

      parent&.scroll_to_visible(rect.moved_by(self.rect.top_left))
    end

    # @return [Color, Theme::Ref, Hash{Symbol => Color, Theme::Ref}, Symbol, nil]
    #   this component's own background — the value as set, so a {Theme::Ref}
    #   comes back unresolved and a state map comes back a Hash; `nil` when
    #   unset, in which case the widget's own well and then the parent answer.
    def bg_color = @bg.color

    # Tints this component and every descendant that doesn't set its own
    # background — set it once on a container / {Component::Popup} to tint a
    # whole subtree. Invalidates the subtree so it repaints.
    #
    # A {Theme::Ref} is re-resolved against the theme each paint, so it tracks
    # light/dark flips with no {#handle_theme_changed} hook; a {Color} is fixed:
    #
    #   panel.bg_color = Theme.ref(:panel_bg)   # theme-tracked
    #   panel.bg_color = Color::GREY27          # fixed
    #
    # A Hash keyed by {ComponentBackground::STATES} gives a color per state —
    # the shape a widget that highlights itself on focus needs, and the reason
    # setting a flat color on one is a *choice* rather than a trap:
    #
    #   field.bg_color = grey                            # flat: focused or not
    #   field.bg_color = { normal: grey, active: blue }  # the pair
    #   field.bg_color = { active: blue }                # keep the widget's own
    #                                                    # well, override focus
    #
    # A state whose key is absent is not answered here at all: resolution falls
    # through to the widget's own well and then to the parent, exactly as `nil`
    # does. That is what makes the third line above mean what it reads as.
    #
    # This does *not* win over a validation error: {#error_bg_color} resolves
    # first, so tinting a panel cannot switch off the error well on the fields
    # inside it. {ComponentBackground} carries the whole chain.
    #
    # @param color [Color, Theme::Ref, Hash, Symbol, Integer, Array<Integer>, nil]
    #   a {Theme::Ref}, {ComponentBackground::INHERIT}, a state Hash, else a
    #   color coerced via {Color.coerce}; `nil` unsets.
    # @raise [ArgumentError] when a Hash carries a key outside
    #   {ComponentBackground::STATES}.
    # @raise [KeyError] when a {Theme::Ref} names an absent custom token —
    #   validated eagerly at assignment, not deferred to paint.
    # @return [void]
    def bg_color=(color)
      @bg.color = color
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
    # That saving is a *leaf*'s: a container's children paint its extent for it,
    # so a cell among them that none covers still gets blanked — an extent
    # narrows which cells are yours, never whether your gaps are wiped.
    #
    # **The children are re-invalidated whether or not they tile.** A container
    # that paints nothing of its own can only redraw its area *through* them, so
    # a tiling container that skipped this would be a dead end in the cascade: an
    # ancestor's background clear wipes the whole ancestor rect — siblings and
    # grandchildren included — and re-invalidates only its *direct* children, so
    # the notice has to keep travelling down or the cleared cells are never
    # repainted. Cheap by construction: repainting the same glyphs leaves
    # {Buffer::Cell} unchanged, so nothing extra reaches the wire.
    #
    # A container that skips `super` because it paints its own rect must still
    # call {#invalidate_children} — that is the half of this that cannot be
    # dropped.
    #
    # **Paint onto `canvas`, never onto {Screen#canvas} by name.** It arrives
    # already loaded with this component's {ComponentBackground#effective}, so every write
    # through it inherits; reach for the screen's own and inheritance silently
    # stops (`D_canvas`).
    #
    # **The canvas paints in this component's own coordinates**: `(0, 0)` is {#rect}'s
    # top-left, so `rect.left` has no place in a `repaint` — adding it lands
    # the write at twice the offset, with nothing raising. {#local_rect} is
    # the region argument to reach for; {Canvas} carries the two spaces.
    # @param canvas [Canvas] the paint context, from {Screen#canvas_for}.
    #   Required: a canvas carries state, so there is no default worth inventing.
    # @return [void]
    def repaint(canvas)
      return if rect.empty?

      unless children.any? && children_tile_rect?
        clear_outside_extent(canvas)
        clear_inside_extent(canvas) if extent && children.any?
      end
      invalidate_children
    end

    # Called when a key is pressed; override to act on keys you care about (the
    # default reports every key unhandled). A component only receives keys while
    # it's on the focus chain — or when app code hands it one directly — so act
    # on the key alone and never gate on your own {#active?} state. See book ch5
    # for how a keystroke is routed to reach here.
    #
    # The `?` reads like `Set#add?`: calling it *delivers* the key and reports
    # whether it was taken, so it is never a "would you handle this?" probe.
    # @param _key [String] a key.
    # @return [Boolean] true if the key was handled, false if not.
    def handle_key?(_key)
      false
    end

    # Called when text is pasted while this component is {Screen#focused};
    # override to accept it. The default drops the text. It arrives whole and
    # `\n`-normalized, so `text.lines.size` is the paste's line count and a
    # single mutation can absorb it:
    #
    #   def handle_paste(text)
    #     self.caption = "[Pasted #{text.lines.size} lines]"
    #   end
    #
    # **No verdict, unlike {#handle_key?}**: a paste reaches the focused component
    # and stops, so one that declines has nowhere to hand it on to
    # (`D_bracketed_paste`).
    #
    # Reaching here means the terminal said "this came from the clipboard" —
    # {Component::AbstractStringField} inserts it at the caret, which is why a
    # subclass that rebinds ENTER to submit needs no paste handling of its own
    # to stop firing once per pasted line.
    # @param _text [String] the pasted text.
    # @return [void]
    def handle_paste(_text); end

    # Called when a mouse button goes down over this component; answer `true` to
    # claim the press. The default claims nothing.
    #
    #   def handle_mouse_down?(event)
    #     return false unless event.button == :left
    #
    #     on_click.fire(ClickEvent.new(source: self))
    #     true
    #   end
    #
    # {Mouse::Router} delivers it to the innermost component under the pointer
    # and bubbles it up the ancestors until one answers `true`; the claimant
    # then holds the *grab*, and the button's {#handle_mouse_drag} and
    # {#handle_mouse_up} go to it alone. The press has already moved focus by
    # the time it arrives, and it only arrives where {#extent_rect} contains the
    # point, so an override needs neither `super` nor a hit test of its own.
    #
    # Activate here, on the press: Tuile synthesizes no click, because a release
    # is losable over ssh and tmux (`D_mouse_dispatch`).
    # @param _event [Mouse::DownEvent]
    # @return [Boolean] whether this component claimed the press.
    def handle_mouse_down?(_event) = false

    # Called when the wheel turns over this component; answer `true` to consume
    # the notch. Bubbles exactly as {#handle_mouse_down?} does, but grabs
    # nothing — so a scroller already at its limit answers `false` and its
    # ancestor scrolls instead.
    # @param _event [Mouse::ScrollEvent]
    # @return [Boolean] whether this component consumed the notch.
    def handle_mouse_scroll?(_event) = false

    # Called when the pointer moves over this component with nothing grabbed;
    # answer `true` to consume the move. Bubbles as {#handle_mouse_down?} does.
    # Arrives only under `run_event_loop(capture_mouse: :hover)`, at up to ~84
    # events a second, which is why the default passes it on untouched.
    # @param _event [Mouse::MoveEvent]
    # @return [Boolean] whether this component consumed the move.
    def handle_mouse_move?(_event) = false

    # Called on the component that claimed a press when the button comes up,
    # ending the grab. For press feedback and for ending a drag — never for
    # activation: a release may never arrive, and any key or the next press
    # ends the grab without it.
    # @param _event [Mouse::UpEvent]
    # @return [void]
    def handle_mouse_up(_event); end

    # Called on the component that claimed a press whenever the pointer moves
    # while the button is held, wherever the pointer is. Needs
    # `capture_mouse: :drag` or `:hover`.
    # @param _event [Mouse::DragEvent] its point may lie outside {#rect}.
    # @return [void]
    def handle_mouse_drag(_event); end

    # Called when the pointer comes over this component or any of its
    # descendants — down the chain, root first, and after every
    # {#handle_mouse_exit} the same move fires. Needs `capture_mouse: :hover`,
    # and is suspended while a press is grabbed.
    #
    # **Never a commit point**: no terminal reports the pointer leaving the
    # window, so the matching {#handle_mouse_exit} may arrive late or not at
    # all. Anything done here must be cosmetic and survive that.
    # @return [void]
    def handle_mouse_enter; end

    # The other half of {#handle_mouse_enter}; also fires when this component is
    # detached or hidden while hovered, innermost first.
    # @return [void]
    def handle_mouse_exit; end

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

    # Final: the parent chain is one half of the tree's single source of truth
    # — {#attached?} walks it while every subtree walk uses {#children}, so a
    # derived pointer leaves a component attached but never painted, with
    # nothing raising (`D_final_tree`). Reparent through {#add_child} /
    # {#remove_child} / {#detach_child}.
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
    # Final: a container that computed this from its own slots would disagree
    # with the parent pointers {#attached?} walks, silently (`D_final_tree`).
    # Named slots are readers *over* this array (`Window#footer`), never a
    # second copy of it; for a swappable region hold a {Slot}.
    # @return [Array<Component>] child components. Must not be mutated by
    #   callers! May be empty.
    attr_reader :children

    # Calls block for this component and for every descendant component.
    # @yield [component]
    # @yieldparam component [Component]
    # @yieldreturn [void]
    # @return [void]
    def walk_tree(&block)
      block.call(self)
      children.each { _1.walk_tree(&block) }
    end

    # {#walk_tree}, pruned: a hidden subtree is skipped whole, this component
    # included when it is itself hidden (in which case nothing is yielded).
    #
    #   stops = []
    #   scope.walk_shown_tree { |c| stops << c if c.tab_stop? }
    #
    # **Use this for anything asking "can the user reach it"**, {#walk_tree} for
    # what the framework does *to* a component regardless — lifecycle, theme
    # fan-out, invalidation — which a hidden component still gets. Writing the
    # first as `walk_tree` plus a `visible?` test is the trap: that is this walk
    # with the ancestor case missing, so a field under a hidden panel is back
    # in the Tab cycle (`D_visibility`).
    # @yield [component]
    # @yieldparam component [Component]
    # @yieldreturn [void]
    # @return [void]
    def walk_shown_tree(&block)
      return unless visible?

      block.call(self)
      children.each { _1.walk_shown_tree(&block) }
    end

    # Called when the component receives focus — on this component alone, never
    # on the ancestors that light up with it. {#handle_blur} is the other half.
    #
    # Unlike `handle_blur` it is **not** edge-triggered: it fires on every
    # {Screen#focused=}, re-assigning the component that already has focus
    # included, which is what lets a container forward focus into its content
    # from here.
    # @return [void]
    def handle_focus; end

    # What {#on_theme_changed} fires.
    #
    # @!attribute [r] source
    #   @return [Component] the component whose theme changed.
    ThemeChangedEvent = Data.define(:source) { include Tuile::Event }

    # What {#on_locale_changed} fires.
    #
    # @!attribute [r] source
    #   @return [Component] the component whose locale changed.
    LocaleChangedEvent = Data.define(:source) { include Tuile::Event }

    # @!method on_theme_changed
    #   Fired by the base {#handle_theme_changed} — the composition-style
    #   alternative to overriding the method, for apps that assemble stock
    #   components rather than subclass:
    #
    #     label.on_theme_changed { label.text = render_status_line }
    #
    #   @return [Listeners]
    listener :on_theme_changed

    # @!method on_locale_changed
    #   Fired by the base {#handle_locale_changed} — the composition-style
    #   alternative to overriding the method, for an app that rendered a date or
    #   a number into a stock component:
    #
    #     label.on_locale_changed { label.text = due_date.strftime(fmt) }
    #
    #   @return [Listeners]
    listener :on_locale_changed

    # Whether this component's tree is mounted on a UI, {ScreenPane} being the
    # root of every displayed tree.
    #
    # A property of the parent chain alone — no {Screen} is consulted, so
    # assembling a tree needs no screen in the process at all:
    #
    #   layout = Component::Layout::Vertical.new
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
    #
    # **{#visible=} reuses this when it hides a subtree holding focus** — the
    # same question, answered once so hide and remove can't drift apart. It
    # passes the *hidden* child, which is still in `children` with `self` as
    # its parent: an override may repair focus however it likes, but must not
    # assume the child is gone. Removal bookkeeping belongs in the remover.
    #
    # The one hook whose base body does real work, so an override *replaces* it
    # (as {Component::Slot} and {ScreenPane} do) instead of calling `super`.
    # @param child [Component] the just-detached, or just-hidden, child.
    # @return [void]
    def handle_child_removed(child)
      return unless attached?

      f = screen.focused
      return if f.nil?

      cursor = f
      until cursor.nil?
        if cursor == child
          screen.focused = self
          break
        end
        cursor = cursor.parent
      end
    end

    # Where the hardware terminal cursor should sit when this component is the
    # cursor owner, **in this component's own coordinates** — the ones it paints
    # in, so a caret is `Point.new(column, row)` with no position added.
    # {Screen#cursor_position} converts it. Returns `nil` to hide the cursor.
    #
    # The {Screen} positions the hardware cursor after each repaint cycle by
    # consulting the {Screen#focused} component only.
    # @return [Point, nil] in this component's coordinates, or nil to hide.
    def cursor_position = nil

    # One line naming the component, its {#id} and its rect, plus whatever
    # {#inspect_details} adds:
    #
    #   #<Tuile::Component::Button id=:save rect=(2,3 8x1) caption="Save">
    #
    # Deliberately shallow — it never walks {#parent} or {#children}, so
    # inspecting one component does not dump the whole UI.
    # @return [String]
    def inspect
      parts = [self.class.to_s] # not .name — an anonymous class has none
      parts << "id=#{@id.inspect}" unless @id.nil?
      parts << "rect=(#{rect})"
      "#<#{(parts + inspect_details).join(" ")}>"
    end

    protected

    # What this component adds to its {#inspect}, as `key=value` strings.
    #
    #   def inspect_details = super + ["items=#{items.size}"]
    #
    # **Always `super`** — this is the seam several mixins share, and each one
    # appends to what the last returned. Override {#inspect} instead of this
    # and you drop whichever details the mixins contribute. They come out in
    # reverse include order, the last-included module running first.
    #
    # The base contributes a bare `hidden` when {#visible?} is false, and
    # nothing when it is true — so in a {Testing.dump} the marker sits on the
    # hidden ancestor, not on each component under it.
    # @return [Array<String>]
    def inspect_details = @visible ? [] : ["hidden"]

    # Adopts `child`: places it in {#children} and wires its parent pointer.
    #
    #   add_child(content, at: 0)   # the tiled layer, painted beneath …
    #   add_child(@footer)          # … and chrome appended, painted over it
    #
    # @param child [Component] must not already have a parent.
    # @param at [Integer, nil] index to insert at; appends when nil.
    # @raise [TypeError] if `child` is not a {Component}.
    # @raise [ArgumentError] if `child` already has a parent.
    # @raise [Tuile::Error] if `child` is a {Component::Overlay} not being
    #   adopted as one of {ScreenPane#popups}.
    # @return [void]
    #
    # Final: one of the three mutators that write {#children} and the parent
    # pointer in the same call, which is what keeps them in agreement.
    def add_child(child, at: nil)
      raise TypeError, "expected Component, got #{child.inspect}" unless child.is_a? Component
      raise ArgumentError, "#{child} already has a parent #{child.parent}" unless child.parent.nil?

      # An overlay's placement, `open?`, `visible=` and outside-click dismissal
      # all come from the pane's popup list, so anywhere else it would be
      # unplaceable and undismissable. Membership, not the pane's identity,
      # which would let the `content` slot through; checked before the push, so
      # a refusal leaves the tree untouched.
      if child.is_a?(Component::Overlay) && !(is_a?(ScreenPane) && has_popup?(child))
        raise Tuile::Error, "#{child.class} belongs on the popup stack — open it (#{child.class}#open) " \
                            "rather than adding it to #{self.class}"
      end
      at.nil? ? @children.push(child) : @children.insert(at, child)
      child.parent = self
      invalidate_layout
    end

    # Drops `child` and notifies {#handle_child_removed}.
    # @param child [Component]
    # @raise [ArgumentError] if `child` is not a child of this component.
    # @return [void]
    #
    # Final: one of the three mutators that write {#children} and the parent
    # pointer in the same call, which is what keeps them in agreement.
    def remove_child(child)
      detach_child(child)
      handle_child_removed(child)
    end

    # Drops `child` *without* notifying — for a container swapping a named slot,
    # which owes the {#handle_child_removed} call once the new occupant is wired:
    #
    #   detach_child(old)
    #   @content = new
    #   add_child(new, at: 0)
    #   handle_child_removed(old)   # focus repair cascades into the *new* content
    #
    # The child leaves {#children} before its pointer is cleared, so nothing
    # observes a child whose parent has disowned it while still listing it.
    # @param child [Component]
    # @raise [ArgumentError] if `child` is not a child of this component.
    # @return [void]
    #
    # Final: one of the three mutators that write {#children} and the parent
    # pointer in the same call, which is what keeps them in agreement.
    def detach_child(child)
      raise ArgumentError, "#{child} is not a child of #{self}" unless @children.include?(child)

      @children.delete(child)
      child.parent = nil
      invalidate_layout
    end

    # Called once this component's tree has been mounted on a {ScreenPane},
    # i.e. when {#attached?} flips to true — the place to acquire whatever is
    # supposed to live for exactly as long as the component is on screen:
    #
    #   def handle_attached
    #     @ticker = screen.event_queue.tick_fps(10) { advance }
    #   end
    #
    #   def handle_detached
    #     @ticker&.cancel
    #     @ticker = nil
    #   end
    #
    # `handle_attached` starts what `handle_detached` stops; both must be cheap and
    # idempotent, since a component moved between parents is genuinely detached
    # in between and gets both, in that order. Whatever you acquire here you
    # must release in {#handle_detached} — nothing else will. Not a destructor:
    # process teardown does *not* fire {#handle_detached}.
    #
    # {#invalidate} needs no guard: {#attached?} is already true here (and
    # already false in {#handle_detached}, where it no-ops). Do not read {#rect} —
    # a parent assigns it *after* wiring, so it is still stale. Runs on the
    # thread that owns the UI.
    # @return [void]
    def handle_attached; end

    # Mirror of {#handle_attached}, called once the tree has been unmounted — see
    # there for the contract. Two things are still mid-flight when it runs, both
    # deliberate: {Screen#focused} may still point into this subtree (repair
    # happens after), and the ex-parent's own bookkeeping may not be finished.
    # So release resources here and don't inspect the tree around you.
    # @return [void]
    def handle_detached; end

    # Rewires the parent pointer and, when that changes whether the component is
    # {#attached?}, fires {#handle_attached} / {#handle_detached} across the whole
    # subtree. The sole firing site: `add_child` / `detach_child` are the only
    # callers, and they update {#children} *before* calling this, so a hook sees
    # a tree whose list and pointers already agree.
    #
    # Reparenting inside an already-attached tree fires nothing (attachedness
    # doesn't change), and neither does building a detached tree.
    # @param new_parent [Component, nil]
    # @return [void]
    #
    # Final: being the sole firing site is the whole contract — an override
    # would fire the lifecycle hooks for the wrong set, or not at all.
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
    #   it would never hear `handle_detached` at all. The reverse case (pulled out
    #   during an *attach* walk) gets `handle_detached` from its own `parent=` and no
    #   `handle_attached`, which is why the hooks are required to be idempotent: an
    #   unpaired detach releases nothing, whereas firing `handle_attached` at a
    #   component that is no longer attached would start a ticker nothing stops.
    #
    # @param attached [Boolean] true to fire {#handle_attached}, false for {#handle_detached}.
    # @return [void]
    def fire_lifecycle(attached)
      kids = children.dup
      attached ? handle_attached : handle_detached
      # A mark taken while detached had no screen to go to; hand it over now
      # that there is one (the `attached?` re-check covers a hook that detached
      # us again). Flutter's `RenderObject#attach` does the same.
      screen.invalidate_layout(self) if attached && @layout_dirty && attached?
      kids.each { _1.fire_lifecycle(attached) if _1.attached? == attached }
    end

    # Called once the parent has given this component a different rect, before
    # anything repaints. Does nothing by default.
    #
    # The *edge*: for a reaction to the change itself, one that needs the old
    # rect or must not repeat — closing a menu, escalating a repaint. State
    # that merely *follows* from the size — a wrap, a scroll clamp — is
    # re-derived in {#relayout} instead, which runs after every rect change
    # on either axis and after every other mark too.
    # @param _old_rect [Rect] the rect it had.
    # @return [void]
    def handle_rect_changed(_old_rect); end

    # Mirror of {#handle_focus}: the component just lost focus, to another component
    # or to nothing. The commit point a Tab-away still reaches — Tab is
    # unconditional, so {Component::TextField#on_enter} never fires for a user
    # who tabs out of a half-typed field:
    #
    #   class TrimmedField < Component::TextField
    #     protected def handle_blur
    #       super
    #       self.value = text.strip
    #       false
    #     end
    #   end
    #
    # Edge-triggered, and fired on the blurred component alone — never on the
    # ancestors leaving the active chain with it, so a composed widget asking
    # "did focus leave me *and* my children" overrides {#active=} instead
    # ({Component::ComboBox} closes its dropdown from there). Focus that merely
    # *passes through* does blur: a container forwarding focus from {#handle_focus}
    # is blurred by its own forward.
    #
    # A notification, not a veto — focus has already moved, and the active-flag
    # cascade has already run. Reassigning {Screen#focused} from here is
    # honored: that assignment wins, and the one that blurred you abandons the
    # rest of its work.
    #
    # == Implementation details
    #
    # It fires wherever focus is *dropped*, not only where a user moved it, so
    # two paths reach it with the tree mid-flight: the popup-close repair blurs
    # an **already-detached** component, where {#invalidate} is the same silent
    # no-op as in {#handle_detached}, and {Screen#close} blurs on its way out. Keep
    # it cheap; a raise propagates out of {Screen#focused=}. Protected because
    # the framework calls it and an app never does — {Screen} reaches it with
    # `__send__`, so an override may declare any visibility (`D_hook_visibility`).
    # @return [void]
    def handle_blur; end

    # Called on every attached component (pre-order, popups included) when
    # {Screen#theme} changes — at {Screen#theme=} / {Screen#theme_def=} and on
    # OS appearance flips. The hook exists for app *content* whose colors were
    # baked in from the old theme (a {Label#text} / {List#lines=} {StyledString}
    # styled with `theme[:accent]`); rebuild it here by re-running the code that
    # rendered it. See book ch6 for why built-in accents need no such handling.
    #
    # Runs on the UI thread with {Screen#theme} already updated, so mutating
    # content (`text=`, `lines=`, …) is safe. Do not assign {Screen#theme=}
    # here. Subclasses overriding this must call `super` so any
    # {#on_theme_changed} listener keeps firing.
    #
    # Plumbing an app overrides and never calls, hence protected — and
    # {Screen}, not being a {Component}, fans it out through `__send__`, so an
    # override is free to declare any visibility (`D_hook_visibility`).
    # @return [void]
    #   is whatever the app's lambda happened to return.
    def handle_theme_changed
      on_theme_changed.fire(ThemeChangedEvent.new(source: self))
    end

    # Called on every attached component (pre-order, popups included) when
    # {Screen#locale} changes — for state derived from the old conventions and
    # **pushed** somewhere, such as a date already rendered into a {Label}'s
    # text. Anything read at paint or parse time needs no override: the locale
    # change invalidates the whole tree.
    #
    # Runs on the UI thread with {Screen#locale} already updated. Subclasses
    # overriding it must call `super` so any {#on_locale_changed}
    # listener keeps firing.
    #
    # Plumbing an app overrides and never calls, hence protected — {Screen}
    # fans it out through `__send__`, so an override may declare any visibility
    # (`D_hook_visibility`).
    # @return [void]
    #   is whatever the app's lambda happened to return.
    def handle_locale_changed
      on_locale_changed.fire(LocaleChangedEvent.new(source: self))
    end

    # The formatting conventions to render and parse by ({Screen#locale}), or
    # {Locale::ISO} when there is no screen in the process — which a tree
    # assembled outside a UI legitimately is, and {Screen.instance} raises
    # rather than answering. Read it here, at use time; never cache it, since
    # {Screen#locale=} can replace it.
    # @return [Locale]
    def locale = Screen.instance? ? screen.locale : Locale::ISO

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

    # Marks this container as owing a {#relayout}: its children's rects are out
    # of date, and the next {#flush_layout} will bring them up to date.
    #
    #   def spacing=(cells)
    #     @spacing = cells
    #     invalidate_layout      # every input to the arithmetic ends here
    #   end
    #
    # The framework marks after `rect=`, after the three tree mutators and
    # after a child's {#visible=} flips; a container marks for every *other*
    # input to its own arithmetic.
    #
    # **The mark never runs the pass** — not even detached, where there is no
    # settle to defer to and {#flush_layout} has to be asked for. That is what
    # lets a constructor `add_child` before its ivars are written, and a
    # container mutate its own bookkeeping in whatever order reads best: no
    # `relayout` ever observes a container mid-configuration.
    #
    # Unlike {#invalidate}, a detached mark is *remembered* rather than
    # dropped: attaching hands it to the {Screen}, so a tree assembled with no
    # screen lays out as soon as it is mounted.
    #
    # **A mark made during this container's own {#relayout}, before it places
    # its first child, is dropped** — the pass that would answer it is the one
    # running. So hide or add a child, or set your own `spacing`, *first*:
    #
    #   def relayout
    #     @sidebar.visible = width >= 60   # before `super`: one pass
    #     super
    #   end
    #
    # Once a child is placed, the division may already be stale, so a later
    # mark is kept and costs a second pass.
    # @return [void]
    def invalidate_layout
      return if LayoutPass.before_first_placement?(self)

      @layout_dirty = true
      screen.invalidate_layout(self) if attached?
    end

    # Assigns every child's rect, and is the only place a container may.
    #
    #   private def relayout
    #     half = width / 2                       # `local_rect`, so no rect.left:
    #     @left.rect  = Rect.new(0, 0, half, height)
    #     @right.rect = Rect.new(half, 0, width - half, height)
    #   end
    #
    # **`relayout` : geometry :: {#repaint} : ink.** Invoked by the framework,
    # never called directly; derives every rect from current state, so it is
    # idempotent and safe to run twice. It assigns *every* child on every pass,
    # including when {#rect} is empty — a `return if rect.empty?` guard strands
    # children at stale coordinates that the next full repaint paints them at
    # (`D_empty_ancestor`).
    #
    # **It is also where a component re-derives what depends on its own size**
    # — a wrap, a padded row cache, a scroll offset clamped to the viewport —
    # because {#rect=} marks the component itself, so this runs after every
    # rect change, width *or* height. It runs after every other mark as well,
    # so a costly derivation keys itself on the size it was built at —
    # {Component::TextView}'s:
    #
    #   def relayout
    #     rewrap unless @wrapped_at == wrap_width   # not on every append
    #     update_scroll_top_row_if_auto_scroll      # a taller viewport moves the bottom
    #     @scrollbar.rect = …
    #   end
    #
    # There is no width-changed hook; {#handle_rect_changed} is the edge, for a
    # reaction to the change itself.
    #
    # Reached through `__send__`, so an override may be protected or private
    # (`D_hook_visibility`). A leaf inherits the empty body and costs nothing.
    # @return [void]
    def relayout; end

    # Whether direct children fully tile {#rect}. Used by the default
    # {#repaint} to decide whether the framework needs to wipe gaps.
    #
    # Approximated by area: sum of (non-empty) child areas vs the parent's
    # area. Cheap, and correct as long as siblings don't overlap each other
    # — which Tuile already requires of a tiled layout.
    # Children with empty rects contribute zero, since they paint nothing.
    #
    # A **hidden** child contributes zero for the same reason, and that is what
    # erases it: its cells become a gap this component then blanks.
    # @return [Boolean]
    def children_tile_rect?
      total = children.sum { |c| c.rect.empty? || !c.visible? ? 0 : c.rect.width * c.rect.height }
      total >= rect.width * rect.height
    end

    # Blanks the part of {#rect} outside {#extent} — the dead tail a widget that
    # paints less than it was given must not leave stale. Up to two regions,
    # since a narrowed extent leaves an L: the columns right of it, and the rows
    # below it. A `nil` extent declares nothing, so the whole rect is blanked.
    # Called by the default {#repaint}; a self-painter that skips `super` calls
    # it directly.
    # @param canvas [Canvas] the paint context, at this component's own background.
    # @return [void]
    def clear_outside_extent(canvas)
      e = extent
      return canvas.fill(local_rect) if e.nil? # nothing declared: all of it is fair game

      right = Rect.new(e.width, 0, rect.width - e.width, e.height)
      below = Rect.new(0, e.height, rect.width, rect.height - e.height)
      # Not this widget's own surface: a one-row Select handed a 25-row rect
      # would otherwise flood the other 24 with its field well.
      canvas.with(bg_color: bg.ambient) do |ambient|
        ambient.fill(right) unless right.empty?
        ambient.fill(below) unless below.empty?
      end
    end

    # Blanks the {#extent} itself, for a *container* whose children don't cover
    # it — a {Component::Layout::Box}'s `spacing` column, the slack past the last
    # child, the span a child abandoned by going hidden or by a narrowing resize.
    #
    # In the *ambient* background, the same answer {#clear_outside_extent} gives
    # the dead tail: a gap between two children is not this widget's ink, so an
    # app's {#bg_color} tint covers it but a well of its own — a field's, a
    # validation error's — must not bleed into it.
    #
    # Called by the default {#repaint} for a container only; a leaf paints its
    # extent itself, and blanking that first is the re-emit `D_progress_bar`
    # bought back. Override it to decline when you paint your own ink into a
    # face cell no child covers.
    # @param canvas [Canvas] the paint context, at this component's own background.
    # @return [void]
    def clear_inside_extent(canvas)
      canvas.with(bg_color: bg.ambient) { _1.fill(local_extent_rect) }
    end

    # This component's background — protected, because stating a widget's own
    # well is the widget's business; an app tints through {#bg_color=}.
    #
    #   bg.default_color = ComponentBackground::INPUT_WELL   # in a field's initialize
    #
    # Final: {Screen#canvas_for} and every descendant's chain read it.
    # @return [ComponentBackground]
    attr_reader :bg

    # The background a component paints while it is in an *error* state —
    # `nil` by default, meaning "I am not signalling one". {HasValidation}
    # overrides it, so every field has it and nothing else does.
    #
    # It sits **above** {#bg_color} in the chain rather than under it, unlike
    # {ComponentBackground#default_color}. That is deliberate: an app tinting a panel
    # would otherwise switch the validation signal off on the fields inside it,
    # silently. An app that wants different error colors changes the
    # {Theme#error_bg_color} tokens.
    #
    # A hook rather than a {ComponentBackground} setter because it follows the
    # validation state, and a pulled answer cannot go stale. Read the theme
    # here rather than in an ivar, and hand back one {Color}: this runs first
    # on every paint.
    # @return [Color, Theme::Ref, Hash, nil]
    def error_bg_color = nil

    # Passes the repaint cascade on to the direct children — the one thing a
    # container may never skip, whatever else its {#repaint} does. Named so a
    # self-painting container can drop the default's blanket clear without also
    # dropping this by accident ({Component::Window} is the case):
    #
    #   def repaint(canvas)
    #     return if rect.empty?
    #
    #     invalidate_children      # never optional
    #     paint_my_own_chrome(canvas)
    #   end
    #
    # @return [void]
    def invalidate_children
      children.each { |c| screen.invalidate(c) }
    end

    private

    # Clears the mark and runs {#relayout} — the sole invocation site of
    # `relayout`, shared by the screen's drain and {#flush_layout}.
    # @return [void]
    def perform_relayout
      @layout_dirty = false
      LayoutPass.run(self) { relayout }
    end

    # The nearest ancestor whose pending {#relayout} would rewrite this
    # component's {#rect}, or `nil` when the rect is current — {#rect_stale?}'s
    # answer, with the culprit kept for {StrictLayout}'s message.
    #
    # Strictly ancestors, never `self`: a container's own flag means its
    # children are stale, and {#perform_relayout} clears the flag before the
    # body runs, so a `relayout` reading its own `width` is asking a settled
    # question.
    # @return [Component, nil]
    def stale_layout_ancestor
      node = parent
      node = node.parent until node.nil? || node.layout_dirty?
      node
    end

    # Hands focus out of the subtree just hidden, if it was in there, through
    # the parent's {#handle_child_removed} — see there for why hiding reuses the
    # removal repair instead of growing a second one. {List#interactive=}
    # reuses it too, for a component that stays shown but stops taking focus.
    #
    # The parent is necessarily showing (focus was inside it a moment ago, and
    # {Screen#focused=} refuses a hidden target), so its assignment can't bounce.
    # @return [void]
    def repair_focus_after_hiding
      return unless attached?

      cursor = screen.focused
      cursor = cursor.parent until cursor.nil? || cursor.equal?(self)
      parent.handle_child_removed(self) unless cursor.nil?
    end
  end
end
