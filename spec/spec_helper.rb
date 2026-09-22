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

# Paints one component — itself, not its children — onto the *screen's* buffer,
# the way {Tuile::Screen#repaint} would. Only for a spec about that buffer: cells
# a repaint must clear, `prints`, the dirty flush, what lands past the rect. What
# a component paints is {Tuile::Testing.paint}.
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
  # Mounts `component` at the size the example wants, under a
  # {Tuile::Component::Layout::Absolute} holder — so the rect sticks. Straight
  # onto `screen.content` it would not: the pane hands its content the whole
  # screen on every pass of its own. A second call on the same component moves
  # it within its holder.
  # @param component [Tuile::Component]
  # @param rect [Tuile::Rect]
  # @return [Tuile::Component] `component`.
  def mount_at(component, rect)
    screen = Tuile::Screen.instance
    case component.parent
    when nil
      holder = Tuile::Component::Layout::Absolute.new
      screen.content = holder
      holder.add(component, rect)
    when Tuile::Component::Layout::Absolute
      component.parent.constrain(component, rect)
    else
      raise ArgumentError, "mount_at: #{component} already sits in #{component.parent}, which places it"
    end
    screen.flush_layout
    component
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.expect_with :minitest
  config.include PaintOne
  config.include DeferredLayout
end
