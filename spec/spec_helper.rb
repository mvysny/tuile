# frozen_string_literal: true

if ENV["COVERAGE"] == "true"
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    enable_coverage :branch
  end
end

require "tuile"
# Not a runtime dependency of the gem — specs use Rainbow.uncolor to strip
# SGR escapes from painted output.
require "rainbow"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.expect_with :minitest
end
