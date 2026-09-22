# frozen_string_literal: true

module Tuile
  # A listener slot: the callables registered on one `on_foo`, fired with one
  # {Event}. The reader *is* the registrar:
  #
  #   button.on_click { save }                         # a block
  #   field.on_value_change << method(:preview)        # anything callable
  #   field.on_value_change.remove(method(:preview))   # …removed, holding nothing
  #   field.on_value_change.empty?                     # => true
  #
  # `Method#==` compares receiver and name, so a widget unsubscribes with the
  # expression it subscribed with and holds nothing. A `Proc` equals only itself,
  # which is why the block form returns the `Proc` it registered rather than the
  # list.
  #
  # Declare one with {Declare}, never by hand. It is not a collection: {#each},
  # {#size} and {#include?} are the whole surface.
  #
  # == There is no setter, and no `clear`
  #
  # The semantics are *append, and remove your own*, and the absent `on_foo=` is
  # the point. A replaceable slot made every claim a contention: wherever the
  # gem wires a listener onto a child it also exposes for tuning
  # (`DateTimeField#date_field`, `RadioGroup#list`, `TabSheet#strip`), an app
  # reaching for that slot silently broke the widget. With no replace operation
  # that failure cannot be written.
  #
  # == An empty list is meaningful, and each slot's rdoc says what its empty means
  #
  # Nothing here reads empty as "nothing to do": while empty, a key-claiming slot
  # declines the key so it keeps bubbling and {Screen#on_error} re-raises.
  # {Declare}'s transition block is for the widget that must *install* something
  # when the slot stops being empty.
  #
  # Duplicates are allowed: two adds fire twice, and one {#remove} balances one
  # {#add}.
  class Listeners
    # A registered callable plus the arity verdict {#fire} needs, settled once
    # at {#add} rather than per fire.
    Entry = Data.define(:callable, :takes_event)
    private_constant :Entry

    # @param name [Symbol] the slot's name (`:on_click`), used in error messages.
    # @yieldparam claimed [Boolean] `true` when the list just became non-empty,
    #   `false` when it just became empty — never called for any other change.
    def initialize(name:, &claim_changed)
      @name = name
      @claim_changed = claim_changed
      @entries = []
    end

    # Appends `callable` and returns it, so a lambda can be held for removal.
    #
    #   cb = field.on_value_change.add(->(e) { preview(e.value) })
    #   field.on_value_change.remove(cb)
    #
    # Arity is settled here rather than per fire, so a listener that cannot take
    # the event raises at registration instead of later inside a repaint on the
    # loop thread.
    #
    # Deliberately does not call `Screen#check_locked`, alone among the gem's
    # mutations: that would mean holding an owner, hence a `Screen` reach inside
    # {Component::HasValue} and {Component::HasValidation}, plain mixins with
    # none.
    #
    # @param callable [#call] the listener.
    # @return [#call] `callable`.
    # @raise [ArgumentError] if it is not callable, or cannot take zero or one
    #   argument.
    def add(callable)
      entry = Entry.new(callable, takes_event?(callable))
      was_empty = @entries.empty?
      @entries << entry
      @claim_changed&.call(true) if was_empty
      callable
    end

    # Appends `callable` and returns self, so registrations chain.
    #
    #   field.on_value_change << method(:preview) << method(:log)
    #
    # @param callable [#call] the listener.
    # @return [self]
    def <<(callable)
      add(callable)
      self
    end

    # Removes the **first** occurrence of `callable`.
    #
    # Not `Array#delete`, which drops every occurrence: one `remove` balances
    # one {#add}, the only rule that composes when a widget and an app happen to
    # register the same `method(:x)`.
    #
    # @param callable [#call] the listener to remove.
    # @return [Boolean] whether it was there.
    def remove(callable)
      index = @entries.index { _1.callable == callable }
      return false if index.nil?

      @entries.delete_at(index)
      @claim_changed&.call(false) if @entries.empty?
      true
    end

    # @param callable [#call]
    # @return [Boolean] whether `callable` is registered.
    def include?(callable) = @entries.any? { _1.callable == callable }

    # @return [Boolean] whether nothing is registered — a state each slot gives
    #   its own meaning.
    def empty? = @entries.empty?

    # @return [Integer] how many listeners are registered, duplicates counted.
    def size = @entries.size

    # Yields each listener in registration order.
    # @yieldparam callable [#call]
    # @return [void]
    def each
      @entries.each { yield _1.callable }
    end

    # Calls every listener in registration order — so the gem's own listener
    # runs before any app's, a widget having wired itself in its constructor.
    #
    # A listener that raises **aborts the fire**: the ones behind it do not run
    # and the exception propagates, as a single slot did. Isolating each
    # listener would turn a bug into a partial fire that nothing reports.
    #
    # @param event [Event] passed to every listener that declared a parameter.
    # @return [void]
    def fire(event)
      # Snapshot: a listener may add or remove during the fire, and the
      # newcomer is meant to run on the *next* one.
      @entries.dup.each { _1.takes_event ? _1.callable.call(event) : _1.callable.call }
    end

    private

    # @param callable [#call]
    # @return [Boolean] whether {#fire} passes it the event.
    # @raise [ArgumentError]
    def takes_event?(callable)
      raise ArgumentError, "#{@name}: expected a callable, got #{callable.inspect}" unless callable.respond_to?(:call)

      arity = callable.is_a?(Proc) || callable.is_a?(Method) ? callable.arity : callable.method(:call).arity
      required = arity.negative? ? -arity - 1 : arity
      if required > 1
        raise ArgumentError, "#{@name}: a listener takes the event or nothing, but #{callable.inspect} requires " \
                             "#{required} arguments"
      end

      # A negative arity means optional or splat parameters, which can absorb
      # the event; only an exact zero declares it wants none.
      !arity.zero?
    end

    # Declares listener slots on the class or module that extends it — what
    # `attr_accessor` is to a plain attribute:
    #
    #   module HasValue
    #     extend Listeners::Declare
    #
    #     # @!method on_value_change
    #     #   Fired whenever the value actually changes — never on a no-op set.
    #     #   @return [Listeners]
    #     listener :on_value_change
    #   end
    #
    # The `@!method` directive is not decoration: a `define_method` reader is
    # invisible to sord, so without it the slot vanishes from `sig/tuile.rbs` —
    # and it is the rdoc the slot owes rubydoc.info anyway.
    #
    # Extending {Component} covers every widget, since a subclass inherits the
    # singleton method.
    module Declare
      # Defines the slot's reader, which returns the {Listeners} — or, given a
      # block, registers it and returns the `Proc`.
      #
      # An optional block is the slot's *transition* block, run on the owner
      # whenever the list becomes non-empty or empty again. It is what lets a
      # widget install a bridge only while somebody is listening:
      #
      #   listener :on_enter do |claimed|
      #     claimed ? editor.on_enter << @bridge : editor.on_enter.remove(@bridge)
      #   end
      #
      # The list is built on first read, so no mixin has to remember a
      # constructor line — which means in-class code goes through the reader and
      # never touches `@on_foo`, nil until somebody asks.
      #
      # @param name [Symbol] the slot's **full** name, `on_`-prefixed. Spelling
      #   it out is what keeps `on_value_change` greppable from its declaration.
      # @yieldparam claimed [Boolean] whether the list just became non-empty.
      # @return [Symbol] `name`.
      # @raise [Error] unless `name` starts with `on_`.
      def listener(name, &claim_changed)
        unless name.to_s.start_with?("on_")
          raise Error, "listener :#{name} — a listener slot is named on_…, and declared this way the string " \
                       "on_#{name} appears nowhere in lib/ for a grep to find. Declare it as :on_#{name}."
        end

        ivar = :"@#{name}"
        define_method(name) do |&block|
          slot = instance_variable_get(ivar)
          unless slot
            owner = self
            transition = claim_changed && ->(claimed) { owner.instance_exec(claimed, &claim_changed) }
            slot = instance_variable_set(ivar, Listeners.new(name: name, &transition))
          end
          block ? slot.add(block) : slot
        end
        name
      end
    end
  end
end
