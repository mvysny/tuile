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
      holder.add(component, rect)
      screen.content = holder
    when Tuile::Component::Layout::Absolute
      component.parent.constrain(component, rect)
    else
      raise ArgumentError, "mount_at: #{component} already sits in #{component.parent}, which places it"
    end
    screen.flush_layout
    component
  end
end

# Puts a component at a rect the only way a rect gets there: through what places
# it. A spec never writes `rect=` — {Tuile::Component#rect=} raises outside the
# parent's `relayout`.
module Placing
  # @param component [Tuile::Component]
  # @param rect [Tuile::Rect] in the parent's coordinates (the screen's, for an
  #   overlay).
  # @return [Tuile::Component] `component`, settled.
  def place(component, rect)
    parent = component.parent
    case parent
    when nil
      return resize_pane(component, rect) if component.is_a?(Tuile::ScreenPane)

      # A root has nothing to place it, so a holder does, and lets go again:
      # the rect it assigned stays.
      holder = Tuile::Component::Layout::Absolute.new
      holder.add(component, rect)
      holder.flush_layout
      holder.remove(component)
    when Tuile::Component::Layout::Absolute
      parent.constrain(component, rect)
    when Tuile::ScreenPane
      if component.is_a?(Tuile::Component::Overlay)
        component.placement = Tuile::Component::Overlay::At[rect]
      else
        holder = Tuile::Component::Layout::Absolute.new
        Tuile::Screen.instance.content = holder
        holder.add(component, rect)
      end
    else
      raise ArgumentError, "place: #{parent} places #{component} itself; constrain it there"
    end
    settle(component)
  end

  private

  # @param pane [Tuile::ScreenPane]
  # @param rect [Tuile::Rect] at the origin, the terminal's new size.
  # @return [Tuile::ScreenPane]
  def resize_pane(pane, rect)
    unless rect.left.zero? && rect.top.zero?
      raise ArgumentError, "place: the pane fills the terminal, so #{rect} must sit at 0,0"
    end

    Tuile::Screen.instance.resize_terminal(rect.width, rect.height)
    pane
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.expect_with :minitest
  config.include PaintOne
  config.include DeferredLayout
  config.include Placing
end
