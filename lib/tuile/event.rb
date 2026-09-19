# frozen_string_literal: true

module Tuile
  # The marker every event includes: *something happened, described by a frozen
  # value*.
  #
  #   class ValueChangeEvent < Data.define(:source, :value)
  #     include Tuile::Event
  #   end
  #
  #   case event
  #   when Mouse::DownEvent then …    # one concrete class
  #   when Tuile::Event     then …    # …or all of them at once
  #   end
  #
  # One concept in three namespaces — {Mouse}'s wire events, {EventQueue}'s loop
  # events, and the ones a {Listeners} slot fires. There is no base class: the
  # `case` above works off the marker alone (`D_mouse_dispatch`).
  #
  # **It mandates no members and supplies no defaults.** `source` belongs to the
  # classes that have one — for the twelve events predating this marker it would
  # be nil throughout, and a member nothing reads is the mailbox shape
  # `D_bad_input` refuses. A default here would be worse than the absence rather
  # than better: `from_user? = false` on the marker would make
  # {Mouse::DownEvent}, the most from-user thing in the gem, answer `false`, and
  # nothing would say so.
  module Event
  end
end
