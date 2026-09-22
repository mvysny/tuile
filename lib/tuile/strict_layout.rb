# frozen_string_literal: true

module Tuile
  # The stale-rect diagnostic: a {Component#rect} read taken while an ancestor
  # still owes a {Component#relayout} says so, instead of handing back the
  # previous pass's rectangle in silence. **On wherever a {FakeScreen} is the
  # installed screen** — a spec suite needs no setup to get it — and off in an
  # app, which {Tuile.strict_layout} overrides either way:
  #
  #   holder.constrain(pane, Rect.new(0, 0, 100, 26))
  #   pane.left.rect        # => Tuile::Error: read the rect of #<Tuile::Component::Label
  #                         #    rect=(0,0 80x50)> while #<TwoPane rect=(0,0 100x26)> owes a
  #                         #    relayout … at spec/two_pane_spec.rb:42
  #
  # `:warn` logs the same line to {Tuile.logger} and hands the rectangle over,
  # for watching a running app; `:raise` is the default and what a spec wants,
  # since the backtrace names the read and a suite that never set a logger
  # would see nothing at all. For the read that is pre-settle *on purpose*,
  # {Tuile.without_strict_layout}.
  #
  # Reading `size`, `width`, `height`, `local_rect`, `absolute_rect` or
  # `to_screen` reports too — they all go through the one reader.
  #
  # **Only reads the app makes are reported** ({PLUMBING}): a read `lib/` makes
  # on the app's behalf mid-handler is not the app's to fix.
  #
  # == Implementation details
  #
  # {Tuile.strict_layout=} and {FakeScreen} prepend this module into
  # {Component}, so `rect` stays the bare `attr_reader` — the hottest read in
  # the toolkit — in every process that never asks. Nothing unprepends; turning
  # the mode off leaves the check inert. See `D_strict_layout`.
  module StrictLayout
    # Where the gem's own frames live, so the site the message names is the
    # app's — `to_screen` and the `size` / `width` / `height` trio all read
    # `rect` from inside `component.rb`.
    # @return [String]
    LIB_DIR = File.expand_path("..", __dir__)

    # The thread-local marking a report in progress: {Component#inspect} prints
    # the rect, so building the message re-enters `rect` on the very component
    # that is being complained about.
    # @return [Symbol]
    REPORTING = :tuile_strict_layout_reporting

    # The readers that only forward to `rect`. A frame of one of these between
    # the read and the app's own code carries no decision of the framework's, so
    # the read still counts as the app's.
    # @return [Array<String>]
    PLUMBING = %w[rect size width height local_rect local_extent_rect absolute_rect absolute_extent_rect
                  to_screen to_local].freeze

    class << self
      # Makes {Component#rect} consult {Tuile.strict_layout} — idempotent, and
      # permanent for the process.
      # @return [void]
      def install = Component.prepend(self)

      # Reports `component`'s rect read as stale, the way `mode` asks for.
      #
      # @param component [Component] the component whose rect was read.
      # @param ancestor [Component] the ancestor owing the relayout.
      # @param mode [Symbol] `:raise` or `:warn`.
      # @raise [Error] in `:raise` mode, unless the read was the framework's own.
      # @return [void]
      def report(component, ancestor, mode)
        return unless app_read?

        message = message_for(component, ancestor)
        raise Error, message if mode == :raise

        Tuile.logger.warn(message)
      end

      private

      # @param component [Component]
      # @param ancestor [Component]
      # @return [String]
      def message_for(component, ancestor)
        Thread.current[REPORTING] = true
        "Tuile: read the rect of #{component.inspect} while #{ancestor.inspect} owes a relayout — " \
          "that rectangle is the previous pass's. Call flush_layout before reading it (a spec), or " \
          "read it after the next event (an app)#{site}"
      ensure
        Thread.current[REPORTING] = false
      end

      # Whether the app asked the question rather than the framework on its
      # behalf: the frames between the read and the first one outside the gem
      # are {PLUMBING} and nothing else.
      # @return [Boolean]
      def app_read?
        frames.each do |frame|
          return true unless frame.path.start_with?(LIB_DIR)
          return false unless PLUMBING.include?(frame.base_label)
        end
        false
      end

      # @return [String] ` at <path>:<line>` for the frame that made the read,
      #   or `""` when there is none outside the gem.
      def site
        frame = frames.find { !_1.path.start_with?(LIB_DIR) }
        frame.nil? ? "" : " at #{frame.path}:#{frame.lineno}"
      end

      # The stack above this file, asked from wherever in it — dropping our own
      # frames by path rather than by a `caller_locations` offset, which would
      # be two different numbers and would drift on any refactor here.
      # @return [Array<Object>] `Thread::Backtrace::Location`s.
      def frames = caller_locations.drop_while { _1.path == __FILE__ }
    end

    # {Component#rect}, reporting first when it is about to answer the previous
    # pass's rectangle.
    # @return [Rect]
    def rect
      mode = Tuile.strict_layout
      if mode && !Thread.current[REPORTING]
        ancestor = stale_layout_ancestor
        StrictLayout.report(self, ancestor, mode) unless ancestor.nil?
      end
      super
    end
  end
end
