# frozen_string_literal: true

module Tuile
  class Component
    # When a text-like field tells its app the value changed. Typing is
    # *held* until the user is done with the field, per {#value_change_mode}:
    #
    #   search = Component::TextField.new
    #   search.value_change_mode                                 # => :commit, the default
    #   search.value_change_mode = :lazy                         # a filter box:
    #   search.on_value_change { |e| filter_results(e.value) }  # 0.4 s after the last key
    #
    # Only the *notice* waits: {HasValue#value} is live whatever the mode, so a
    # Save handler reading it gets what is on screen. Held are **edits** — keys
    # and a paste, while the field is on the focus chain; a write through
    # {HasValue#set_value} (a program, an Up/Down step, `Testing.set_value`)
    # announces at once, and so does an edit reaching a field that isn't
    # focused, which has no commit gesture coming.
    #
    # Included by the string fields and the number fields. The date and time
    # fields carry no knob: they always hold, because a prefix of a date can
    # parse into a wrong one (`design/decisions.md` `D_value_change_mode`).
    #
    # == Implementation details
    # The includer supplies `fire_if_changed(from_user:)` — the notice with its
    # diff guard, so a release that changed nothing stays silent — and calls
    # the three private hooks from its own paths: `notify_on_edit?` then
    # `hold_edit` on an edit, `announce` on a write and on each commit gesture.
    # The `:lazy` timer is owned by one sync over "an edit is held, the mode
    # is lazy, the field is attached", its sole writer.
    module HasValueChangeMode
      # @return [Array<Symbol>] the accepted {#value_change_mode}s.
      MODES = %i[eager commit lazy].freeze

      # @return [Float] {#value_change_timeout}'s default, in seconds —
      #   Vaadin's `LAZY` default.
      DEFAULT_TIMEOUT = 0.4

      # When {HasValue#on_value_change} fires for an edit:
      #
      # - `:eager` — on every edit;
      # - `:commit` (the default) — on a commit gesture: leaving the focus
      #   chain, or ENTER. A {TextArea} commits on leaving only, since ENTER
      #   types a newline there, and so does a subclass that claims ENTER itself;
      # - `:lazy` — once edits pause for {#value_change_timeout}, or at a
      #   commit gesture if that comes first.
      # @return [Symbol] one of {MODES}.
      def value_change_mode = @value_change_mode || :commit

      # A held notice goes out at once on a switch to `:eager`, which never
      # holds one.
      # @param mode [Symbol] one of {MODES}.
      # @return [void]
      # @raise [ArgumentError] on anything else.
      def value_change_mode=(mode)
        raise ArgumentError, "expected one of #{MODES.inspect}, got #{mode.inspect}" unless MODES.include?(mode)

        @value_change_mode = mode
        announce(from_user: true) if @notice_held && mode == :eager
        sync_notice_timer
      end

      # @return [Numeric] how long `:lazy` waits after the last edit, in seconds.
      def value_change_timeout = @value_change_timeout || DEFAULT_TIMEOUT

      # Takes effect from the next edit.
      # @param seconds [Numeric] zero or positive.
      # @return [void]
      # @raise [ArgumentError] unless `seconds` is a non-negative Numeric.
      def value_change_timeout=(seconds)
        unless seconds.is_a?(Numeric) && !seconds.negative?
          raise ArgumentError, "expected a non-negative Numeric, got #{seconds.inspect}"
        end

        @value_change_timeout = seconds
      end

      # @return [void]
      def handle_detached
        super
        sync_notice_timer
      end

      protected

      # @return [Boolean] whether an edit announces now rather than being held.
      def notify_on_edit? = value_change_mode == :eager || !active?

      private

      # Holds the notice for an edit {#notify_on_edit?} declined, restarting a
      # `:lazy` wait.
      # @return [void]
      def hold_edit
        @notice_held = true
        @notice_timer&.cancel
        @notice_timer = nil
        sync_notice_timer
      end

      # Announces the current value, if it differs from the last one announced,
      # and ends any hold.
      # @param from_user [Boolean] what the write declared; `true` at a commit
      #   gesture, which only releases the user's own edits.
      # @return [void]
      def announce(from_user:)
        @notice_held = false
        sync_notice_timer
        fire_if_changed(from_user:)
      end

      # @return [void]
      def sync_notice_timer
        wanted = @notice_held && value_change_mode == :lazy && attached?
        if wanted && @notice_timer.nil?
          @notice_timer = screen.event_queue.after(value_change_timeout) do
            @notice_timer = nil
            announce(from_user: true)
          end
        elsif !wanted && @notice_timer
          @notice_timer.cancel
          @notice_timer = nil
        end
      end
    end
  end
end
