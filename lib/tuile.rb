# frozen_string_literal: true

require "concurrent"
require "io/console"
require "rainbow"
require "set"
require "singleton"
require "strings-truncation"
require "tty-box"
require "tty-cursor"
require "tty-logger"
require "tty-screen"
require "unicode/display_width"
require "zeitwerk"

# Tuile is a small component-oriented terminal UI framework, built on top of
# the TTY toolkit. The name is French for a roof tile — a small piece that
# composes into a larger whole, which mirrors how Tuile UIs are built from
# {Component}s nested under a single {Screen}.
module Tuile
  class Error < StandardError; end

  loader = Zeitwerk::Loader.for_gem
  loader.setup
end
