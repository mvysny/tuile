# frozen_string_literal: true

require "concurrent"
require "date"
require "io/console"
require "logger"
require "singleton"
require "strscan"
require "tty-cursor"
require "tty-screen"
require "unicode/display_width"
require "zeitwerk"

# Tuile is a small component-oriented terminal UI framework, built on top of
# the TTY toolkit. The name is French for a roof tile — a small piece that
# composes into a larger whole, which mirrors how Tuile UIs are built from
# {Component}s nested under a single {Screen}.
module Tuile
  class Error < StandardError; end

  class << self
    # The logger Tuile writes to. Defaults to a null logger, so the gem is
    # silent unless the host app opts in via `Tuile.logger = ...`. Any object
    # duck-typing the stdlib `Logger` interface (`debug/info/warn/error/fatal`
    # taking a string) works — including `TTY::Logger`.
    # @return [Logger]
    attr_writer :logger

    # @return [Logger]
    def logger
      @logger ||= Logger.new(IO::NULL)
    end

    # How a pre-settle {Component#rect} read is reported: `false`, `:warn` to
    # {#logger}, or `:raise`. Unset — which is how a process starts — answers
    # the default: **`:raise` under a {FakeScreen}**, where a spec suite is the
    # audience, and `false` anywhere else. See {StrictLayout}.
    # @return [Symbol, false]
    def strict_layout
      return @strict_layout unless @strict_layout.nil?

      Screen.instance? && Screen.instance.is_a?(FakeScreen) ? :raise : false
    end

    # Chooses for the whole process, overriding that default either way —
    # `true` means `:raise`, and `nil` hands the choice back:
    #
    #   Tuile.strict_layout = :warn     # a running app, being watched
    #   Tuile.strict_layout = false     # a spec suite that wants none of it
    #
    # A mode that isn't `false` prepends {StrictLayout} into {Component}, which
    # is permanent for the process; `false` afterwards makes the check inert
    # rather than removing it.
    # @param mode [Symbol, Boolean, nil] `:warn`, `:raise`, `false`, or `nil`
    #   for the default.
    # @raise [ArgumentError] on any other value.
    # @return [void]
    def strict_layout=(mode)
      mode = :raise if mode == true
      unless [nil, false, :warn, :raise].include?(mode)
        raise ArgumentError, "expected :warn, :raise, false or nil, got #{mode.inspect}"
      end

      StrictLayout.install if mode
      @strict_layout = mode
    end

    # Runs the block with the diagnostic off, for a *spec's* read taken
    # pre-settle *on purpose* — asserting that a rect survived a round trip is a
    # question only the unsettled value answers:
    #
    #   Tuile.without_strict_layout { assert_equal rect, second.rect }
    #
    # A test tool, not app code: the diagnostic is on only under a {FakeScreen}
    # or after {.strict_layout=}, so an app's stale read wants settling, not
    # silencing. Restores whatever was in force, default included, and silences
    # every read in the block, on this thread and any other.
    # @return [Object] the block's value.
    def without_strict_layout
      previous = @strict_layout
      @strict_layout = false
      yield
    ensure
      @strict_layout = previous
    end
  end

  loader = Zeitwerk::Loader.for_gem
  # Keeps Tuile's one optional dependency optional: the file requires
  # `bigdecimal` at load, so a host app calling Zeitwerk::Loader.eager_load_all
  # would otherwise raise LoadError for a component it never names.
  loader.do_not_eager_load("#{__dir__}/tuile/component/big_decimal_field.rb")
  loader.setup
end
