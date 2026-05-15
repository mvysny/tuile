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
  # Modal popups are supported too, via {Component::Popup#open}. They
  # auto-size to their wrapped content and are drawn centered over the
  # tiled content.
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
      @size = EventQueue::TTYSizeEvent.create.size
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

    # @return [Size] current screen size.
    attr_reader :size

    # @return [Array<Component>] currently active popup components (forwarded
    #   to {ScreenPane}). The array must not be modified!
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
      # Popups own their own "q Close" prefix in #keyboard_hint; for the tiled
      # case Screen tacks on the global "q quit" instead.
      top_popup = @pane.popups.last
      @pane.status_bar.text = if top_popup.nil?
                                "q #{Rainbow("quit").cadetblue}  #{active_window&.keyboard_hint}".strip
                              else
                                top_popup.keyboard_hint
                              end
    end

    # Internal — use {Component::Popup#open} instead. Adds the popup to
    # {#pane}, centers and focuses it.
    # @api private
    # @param window [Component::Popup]
    # @return [void]
    def add_popup(window)
      check_locked
      @pane.add_popup(window)
      # No need to fully repaint the scene: a popup simply paints over the
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

    # Advances focus to the next {Component#tab_stop?} in tree order, wrapping
    # around. Scope is the topmost popup if one is open, otherwise {#content}
    # — this keeps Tab confined inside a modal popup. No-op (returns false) if
    # the modal scope has no tab stops or no content at all.
    # @return [Boolean] true if focus moved.
    def focus_next = cycle_focus(forward: true)

    # Mirror of {#focus_next} that walks backwards through the tab order.
    # @return [Boolean] true if focus moved.
    def focus_previous = cycle_focus(forward: false)

    # @return [Component, nil] current active tiled component.
    def active_window
      check_locked
      result = nil
      @pane.content&.on_tree { result = it if it.is_a?(Component::Window) && it.active? }
      result
    end

    # Internal — use {Component::Popup#close} instead. Removes the popup
    # from {#pane}, repairs focus, and repaints the scene.
    #
    # Does nothing if the window is not open on this screen.
    # @api private
    # @param window [Component::Popup]
    # @return [void]
    def remove_popup(window)
      check_locked
      @pane.remove_popup(window)
      needs_full_repaint
    end

    # Internal — use {Component::Popup#open?} instead.
    # @api private
    # @param window [Component::Popup]
    # @return [Boolean] true if this popup is currently mounted.
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

    # Prints given strings. While {#repaint} is running, writes are
    # accumulated into a frame buffer and flushed to the terminal as a
    # single `$stdout.write` at the end of the cycle. This stops the
    # emulator from rendering half-finished frames (e.g. a layout's
    # clear-background pass before its children have re-painted), which
    # was visible as a brief flicker when the auto-clear path triggers.
    #
    # Outside repaint, writes go straight to stdout. We deliberately
    # don't raise on a "print outside repaint" — that would be a useful
    # guardrail against components painting outside the repaint loop,
    # but it'd force terminal-housekeeping writes (`Screen#clear`,
    # mouse-tracking start/stop, cursor-show on teardown) to bypass
    # this method entirely and write directly to `$stdout`. {FakeScreen}
    # overrides `print` to capture every byte into its `@prints` array,
    # and tests that exercise `run_event_loop` against a real {Screen}
    # would otherwise leak escape sequences to the test runner's stdout.
    # Keeping `print` as the single sink preserves that override seam.
    # @param args [String] stuff to print.
    # @return [void]
    def print(*args)
      if @frame_buffer
        args.each { |s| @frame_buffer << s.to_s }
      else
        Kernel.print(*args)
      end
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
      @frame_buffer = +""
      begin
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
        unless @frame_buffer.empty?
          $stdout.write(@frame_buffer)
          $stdout.flush
        end
      ensure
        # Always release the frame buffer, even on exception, so any
        # subsequent {#print} call (e.g. teardown emits during crash unwind)
        # reaches stdout instead of being swallowed by a stranded buffer.
        # The partial frame we hold here is incoherent — discard it.
        @frame_buffer = nil
      end
    end

    # Returns the absolute screen coordinates where the hardware cursor should
    # sit, or nil if it should be hidden. Only the {#focused} component owns
    # the cursor: there can be multiple active components (the focus path),
    # but only one focused.
    # @return [Point, nil]
    def cursor_position = @focused&.cursor_position

    private

    # Walks the current modal scope in pre-order, collects tab stops, and
    # advances focus by one (wrapping). When the focused component isn't in
    # the tab order (e.g. focus is parked on a popup/window chrome with no
    # interactable widgets), Tab goes to the first stop and Shift+Tab to the
    # last.
    # @param forward [Boolean]
    # @return [Boolean] true if focus moved.
    def cycle_focus(forward:)
      check_locked
      scope = @pane.popups.last || @pane.content
      return false if scope.nil?

      stops = []
      scope.on_tree { |c| stops << c if c.tab_stop? }
      return false if stops.empty?

      idx = @focused.nil? ? nil : stops.index(@focused)
      target = if idx.nil?
                 forward ? stops.first : stops.last
               else
                 stops[(idx + (forward ? 1 : -1)) % stops.size]
               end
      return false if target.equal?(@focused)

      self.focused = target
      true
    end

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
    #
    # Tab / Shift+Tab are reserved navigation keys: intercepted here before
    # the pane sees them, so a focused {Component::TextField} (which would
    # otherwise swallow printable keys via the standard cursor-owner
    # suppression) doesn't trap them.
    # @param key [String]
    # @return [Boolean] true if the key was handled by some window.
    def handle_key(key)
      case key
      when Keys::TAB
        focus_next
        true
      when Keys::SHIFT_TAB
        focus_previous
        true
      else
        @pane.handle_key(key)
      end
    end

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
          @size = event.size
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
