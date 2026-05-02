# frozen_string_literal: true

module Tuile
  # The TTY screen. There is exactly one screen per app.
  #
  # A screen runs the event loop; call {#run_event_loop} to do that.
  #
  # A screen holds the screen lock; any UI modifications must be called from
  # the event queue.
  #
  # All UI lives under a single {ScreenPane} owned by the screen. Set tiled
  # content via {#content=}; the pane fills the entire terminal and is
  # responsible for laying out its children.
  #
  # Modal/popup windows are supported too, via {#add_popup}. They are
  # centered (which means that they need to provide their desired width and
  # height) and drawn over the tiled content.
  #
  # The drawing procedure is very simple: when a window needs repaint, it
  # invalidates itself, but won't draw immediately. After the keyboard press
  # event processing is done in the event loop, {#repaint} is called which
  # then repaints all invalidated windows. This prevents repeated paintings.
  class Screen
    # Class variable (not class instance var) so the singleton survives
    # subclassing — `FakeScreen < Screen` and `Screen.instance` see the same slot.
    @@instance = nil # rubocop:disable Style/ClassVars

    def initialize
      @@instance = self # rubocop:disable Style/ClassVars
      @event_queue = EventQueue.new
      @size = EventQueue::TTYSizeEvent.create
      @invalidated = Set.new
      # Components being repainted right now. A component may invalidate its
      # children during its repaint phase; this prevents double-draw.
      @repainting = Set.new
      # Until the event loop is run, we pretend we're in the UI thread.
      @pretend_ui_lock = true
      # Structural root of the component tree: holds tiled content, popup
      # stack and status bar.
      @pane = ScreenPane.new
      @on_error = ->(e) { raise e }
    end

    # @return [ScreenPane] the structural root of the component tree.
    attr_reader :pane

    # Handler invoked when a {StandardError} escapes an event handler inside
    # the event loop (e.g. a {Component::TextField}'s `on_change` raises).
    #
    # The default re-raises, so the exception propagates out of
    # {#run_event_loop} and crashes the script with a stacktrace — unhandled
    # exceptions are bugs and should be surfaced loudly.
    #
    # Replace it when the host has somewhere visible to put errors, e.g. a
    # {Component::LogWindow} wired to {Tuile.logger}:
    #
    #   screen.on_error = lambda do |e|
    #     Tuile.logger.error("#{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}")
    #   end
    #
    # The handler runs on the event-loop thread with the UI lock held.
    # Returning normally keeps the loop alive; raising from within the handler
    # tears the loop down and propagates out of {#run_event_loop}.
    # @return [Proc] one-arg callable receiving the {StandardError} instance.
    attr_accessor :on_error

    # @return [Screen] the singleton instance.
    def self.instance
      raise Tuile::Error, "Screen not initialized; call Screen.new first" if @@instance.nil?

      @@instance
    end

    # @return [Component, nil] tiled content (forwarded to {ScreenPane}).
    def content = @pane.content

    # @param content [Component]
    # @return [void]
    def content=(content)
      @pane.content = content
      layout
    end

    # @return [EventQueue::TTYSizeEvent] current screen size.
    attr_reader :size

    # @return [Array<Component::PopupWindow>] currently active popup windows
    #   (forwarded to {ScreenPane}). The array must not be modified!
    def popups = @pane.popups

    # @return [EventQueue] the event queue.
    attr_reader :event_queue

    # Checks that the UI lock is held and the current code runs in the "UI
    # thread".
    # @return [void]
    def check_locked
      return if @pretend_ui_lock || @event_queue.locked?

      raise Tuile::Error,
            "UI lock not held: UI mutations must run on the event-loop thread; " \
            "marshal via screen.event_queue.submit { ... }"
    end

    # Clears the TTY screen.
    # @return [void]
    def clear
      print TTY::Cursor.move_to(0, 0), TTY::Cursor.clear_screen
    end

    # Invalidates a component: causes the component to be repainted on next
    # call to {#repaint}.
    # @param component [Component]
    # @return [void]
    def invalidate(component)
      check_locked
      raise TypeError, "expected Component, got #{component.inspect}" unless component.is_a? Component

      @invalidated << component unless @repainting.include? component
    end

    # @return [Component, nil] currently focused component.
    attr_reader :focused

    # Sets the focused {Component}. Focused component receives keyboard events.
    # All focusable components live under {#pane}, so this is a single uniform
    # path (no separate popup-vs-content branches).
    # @param focused [Component, nil] the new component to be focused.
    def focused=(focused)
      unless focused.nil? || focused.is_a?(Component)
        raise TypeError, "expected Component or nil, got #{focused.inspect}"
      end

      check_locked
      if focused.nil?
        @focused = nil
        @pane.on_tree { it.active = false }
      else
        raise Tuile::Error, "#{focused} is not attached to this screen" if focused.root != @pane

        @focused = focused
        active = Set[focused]
        cursor = focused.parent
        until cursor.nil?
          active << cursor
          cursor = cursor.parent
        end
        @pane.on_tree { it.active = active.include?(it) }
        @focused.on_focus
      end
      top_window = @pane.popups.last || active_window
      q_action = @pane.popups.empty? ? "quit" : "close"
      @pane.status_bar.text = "q #{Rainbow(q_action).cadetblue}  #{top_window&.keyboard_hint}".strip
    end

    # @param window [Component::PopupWindow] the popup to add. Will be centered
    #   and painted automatically.
    # @return [void]
    def add_popup(window)
      check_locked
      @pane.add_popup(window)
      # No need to fully repaint the scene: PopupWindow simply paints over
      # current screen contents.
    end

    # Runs event loop – waits for keys and sends them to active window. The
    # function exits when the 'ESC' or 'q' key is pressed.
    # @return [void]
    def run_event_loop
      @pretend_ui_lock = false
      $stdin.echo = false
      print MouseEvent.start_tracking
      $stdin.raw do
        event_loop
      end
    ensure
      print MouseEvent.stop_tracking
      print TTY::Cursor.show
      $stdin.echo = true
    end

    # @return [Component, nil] current active tiled component.
    def active_window
      check_locked
      result = nil
      @pane.content&.on_tree { result = it if it.is_a?(Component::Window) && it.active? }
      result
    end

    # Removes a popup. Repaints the whole scene, which should visually "remove"
    # the window. The window will also no longer receive keys. Focus repair is
    # handled by {ScreenPane#on_child_removed}.
    #
    # Does nothing if the window is not open on this screen.
    # @param window [Component::PopupWindow]
    # @return [void]
    def remove_popup(window)
      check_locked
      @pane.remove_popup(window)
      needs_full_repaint
    end

    # @param window [Component::PopupWindow]
    # @return [Boolean] if screen contains this window.
    def has_popup?(window) # rubocop:disable Naming/PredicatePrefix
      check_locked
      @pane.has_popup?(window)
    end

    # Testing only — creates new screen, locks the UI, and prevents any
    # redraws, so that test TTY is not painted over. {FakeScreen#initialize}
    # self-installs as the singleton, so subsequent {Screen.instance} calls
    # return the same object.
    # @return [FakeScreen]
    def self.fake = FakeScreen.new

    # @return [void]
    def close
      clear
      @pane = nil
      @@instance = nil # rubocop:disable Style/ClassVars
    end

    # @return [void]
    def self.close
      @@instance&.close
    end

    # Prints given strings.
    # @param args [String] stuff to print.
    # @return [void]
    def print(*args)
      Kernel.print(*args)
    end

    # Repaints the screen; tries to be as effective as possible, by only
    # considering invalidated windows.
    # @return [void]
    def repaint
      check_locked
      # This simple TUI framework doesn't support window clipping since tiled
      # windows are not expected to overlap. If there rarely is a popup, we
      # just repaint all windows in correct order — sure they will paint over
      # other windows, but if this is done in the right order, the final
      # drawing will look okay. Not the most effective algorithm, but very
      # simple and very fast in common cases.

      did_paint = false
      until @invalidated.empty?
        did_paint = true
        popups = @pane.popups

        # Partition invalidated components into tiled vs popup-tree. Sorting
        # by depth across the whole tree would interleave them: a tiled
        # grandchild (depth 3) sorts after a popup's content (depth 2) and
        # overdraws it.
        popup_tree = Set.new
        popups.each { |p| p.on_tree { popup_tree << it } }
        tiled, popup_invalidated = @invalidated.to_a.partition { !popup_tree.include?(it) }

        # Within the tiled tree, paint parents before children.
        tiled.sort_by!(&:depth)

        repaint = if tiled.empty?
                    # Only popups need repaint — paint just their invalidated
                    # components in depth order.
                    popup_invalidated.sort_by(&:depth)
                  else
                    # Tiled components may overdraw popups; repaint each open
                    # popup's full subtree on top, in stacking order
                    # (parent-before-child within each popup).
                    tiled + popups.flat_map { |p| collect_subtree(p) }
                  end

        @repainting = repaint.to_set
        @invalidated.clear

        # Don't call {#clear} before repaint — causes flickering, and only
        # needed when @content doesn't cover the entire screen.
        repaint.each(&:repaint)

        # Repaint done, mark all components as up-to-date.
        @repainting.clear
      end
      position_cursor if did_paint
    end

    # Returns the absolute screen coordinates where the hardware cursor should
    # sit, or nil if it should be hidden. Only the {#focused} component owns
    # the cursor: there can be multiple active components (the focus path),
    # but only one focused.
    # @return [Point, nil]
    def cursor_position = @focused&.cursor_position

    private

    # Collects a component and all its descendants in tree order
    # (parent before children).
    # @param component [Component]
    # @return [Array<Component>]
    def collect_subtree(component)
      result = []
      component.on_tree { result << it }
      result
    end

    # Hides or moves the hardware cursor based on the current focus state.
    # @return [void]
    def position_cursor
      pos = cursor_position
      if pos.nil?
        print TTY::Cursor.hide
      else
        print TTY::Cursor.move_to(pos.x, pos.y), TTY::Cursor.show
      end
    end

    # Recalculates positions of all windows, and repaints the scene.
    # Automatically called whenever terminal size changes. Call when the app
    # starts. {#size} provides correct size of the terminal.
    # @return [void]
    def layout
      check_locked
      needs_full_repaint
      @pane.rect = Rect.new(0, 0, size.width, size.height)
      repaint
    end

    # Called after a popup is closed. Since a popup can cover any window,
    # top-level component or other popups, we need to redraw everything.
    # @return [void]
    def needs_full_repaint
      @pane&.on_tree { invalidate it }
    end

    # A key has been pressed on the keyboard. Handle it, or forward to active
    # window.
    # @param key [String]
    # @return [Boolean] true if the key was handled by some window.
    def handle_key(key) = @pane.handle_key(key)

    # Finds target window and calls {Component::Window#handle_mouse}.
    # @param event [MouseEvent]
    # @return [void]
    def handle_mouse(event) = @pane.handle_mouse(event)

    # @return [void]
    def event_loop
      @event_queue.run_loop do |event|
        case event
        when EventQueue::KeyEvent
          key = event.key
          handled = handle_key(key)
          @event_queue.stop if !handled && ["q", Keys::ESC].include?(key)
        when MouseEvent
          handle_mouse(event)
        when EventQueue::TTYSizeEvent
          @size = event
          layout
        when EventQueue::EmptyQueueEvent
          repaint
        end
      rescue StandardError => e
        @on_error.call(e)
      end
    end
  end
end
