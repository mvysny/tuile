# frozen_string_literal: true

require "concurrent"
require "io/console"
require "logger"
require "rainbow"
require "singleton"
require "strings-truncation"
require "tty-box"
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
    attr_writer :logger

    def logger
      @logger ||= Logger.new(IO::NULL)
    end
  end

  loader = Zeitwerk::Loader.for_gem
  loader.setup
end
