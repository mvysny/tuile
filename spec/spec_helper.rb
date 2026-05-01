# frozen_string_literal: true

require "tuile"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.expect_with :minitest
end
