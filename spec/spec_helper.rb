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

# Paints one component the way {Tuile::Screen#repaint} would. There is no other
# way: `Component#repaint` takes a required {Tuile::Canvas}, and that canvas
# carries the component's resolved background (`D_canvas`).
module PaintOne
  # @param component [Tuile::Component]
  # @return [void]
  def repaint(component) = component.repaint(Tuile::Screen.instance.canvas_for(component))
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.expect_with :minitest
  config.include PaintOne
end
