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
  # Settles the layout first, exactly as {Tuile::Screen#repaint} does — paint
  # is the heaviest reader of rects there is, and no event has been dispatched
  # to settle it.
  # @param component [Tuile::Component]
  # @return [void]
  def repaint(component)
    component.flush_layout
    component.repaint(Tuile::Screen.instance.canvas_for(component))
  end
end

# Layout is deferred: a mutation marks, and the loop settles it at the end of
# the event it rode in on. A spec has no such event, so it settles here.
module DeferredLayout
  # @param component [Tuile::Component]
  # @return [Tuile::Component] `component`, its rect current.
  def settle(component) = component.tap(&:flush_layout)

  # Mounts `component` at the size the example wants, under a
  # {Tuile::Component::Layout::Absolute} holder that places nothing — so the
  # rect sticks. Straight onto `screen.content` it would not: the pane hands
  # its content the whole screen on every pass of its own, and *any* later mark
  # (opening a popup, swapping content) replays that.
  # @param component [Tuile::Component]
  # @param rect [Tuile::Rect]
  # @return [Tuile::Component] `component`.
  def mount_at(component, rect)
    screen = Tuile::Screen.instance
    if component.parent.nil?
      holder = Tuile::Component::Layout::Absolute.new
      screen.content = holder
      holder.add(component)
    end
    screen.flush_layout
    component.rect = rect
    settle(component)
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.expect_with :minitest
  config.include PaintOne
  config.include DeferredLayout
end
