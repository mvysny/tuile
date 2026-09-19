# frozen_string_literal: true

module Tuile
  RSpec.describe Listeners do
    # No Screen.fake pair, deliberately: a listener slot has no screen
    # dependency, which is what lets the plain mixins carry one.
    let(:event) { Data.define(:source) { include Tuile::Event }.new(source: :somebody) }

    def slot(&claim_changed) = described_class.new(name: :on_test, &claim_changed)

    describe "registration" do
      it "returns the callable from add, so a lambda can be held" do
        cb = ->(_e) {}
        list = slot
        assert_same cb, list.add(cb)
        assert list.include?(cb)
      end

      it "returns self from <<, so registrations chain" do
        list = slot
        assert_same list, (list << ->(_e) {} << ->(_e) {})
        assert_equal 2, list.size
      end

      it "fires in registration order" do
        order = []
        list = slot
        list << -> { order << :first } << -> { order << :second }
        list.fire(event)
        assert_equal %i[first second], order
      end

      it "reports empty and size" do
        list = slot
        assert list.empty?
        assert_equal 0, list.size
        list << -> {}
        refute list.empty?
        assert_equal 1, list.size
      end

      it "yields the callables themselves, not the entries wrapping them" do
        a = -> {}
        b = -> {}
        list = slot
        list << a << b
        yielded = []
        list.each { yielded << _1 }
        assert_equal [a, b], yielded
      end
    end

    describe "duplicates" do
      it "admits the same callable twice and fires it twice" do
        n = 0
        cb = -> { n += 1 }
        list = slot
        list << cb << cb
        list.fire(event)
        assert_equal 2, n
      end

      it "removes only the first occurrence, so one remove balances one add" do
        cb = -> {}
        list = slot
        list << cb << cb
        assert list.remove(cb)
        assert_equal 1, list.size
        assert list.include?(cb)
      end
    end

    describe "removal" do
      it "answers false for a callable that was never there" do
        refute slot.remove(-> {})
      end

      it "removes a Method without holding it, since Method#== compares receiver and name" do
        target = Object.new
        def target.handle(_event) = nil
        list = slot
        list << target.method(:handle)
        assert list.remove(target.method(:handle))
        assert list.empty?
      end

      it "does not remove the same method name on another receiver" do
        klass = Class.new do
          def handle(_event) = nil
        end
        list = slot
        list << klass.new.method(:handle)
        refute list.remove(klass.new.method(:handle))
      end
    end

    describe "arity" do
      it "calls a zero-parameter listener with nothing" do
        called = false
        list = slot
        list << -> { called = true }
        list.fire(event)
        assert called
      end

      it "passes the event to a one-parameter listener" do
        seen = nil
        list = slot
        list << ->(e) { seen = e }
        list.fire(event)
        assert_same event, seen
      end

      it "passes the event to a splat listener" do
        seen = nil
        list = slot
        list << ->(*args) { seen = args }
        list.fire(event)
        assert_equal [event], seen
      end

      it "passes the event to a listener whose only parameter is optional" do
        seen = :untouched
        list = slot
        list << ->(e = nil) { seen = e }
        list.fire(event)
        assert_same event, seen
      end

      it "treats a zero-parameter proc as taking nothing, not as lenient" do
        args = :untouched
        list = slot
        list << proc { args = :none }
        list.fire(event)
        assert_equal :none, args
      end

      it "rejects a two-parameter listener at registration, not at fire" do
        e = assert_raises(ArgumentError) { slot << ->(_a, _b) {} }
        assert_includes e.message, "on_test"
        assert_includes e.message, "requires 2 arguments"
      end

      it "rejects a listener requiring two of three parameters" do
        assert_raises(ArgumentError) { slot << ->(_a, _b, *_rest) {} }
      end

      it "admits an object that is callable rather than a Proc" do
        callable = Object.new
        def callable.call(event) = (@seen = event)
        def callable.seen = @seen
        list = slot
        list << callable
        list.fire(event)
        assert_same event, callable.seen
      end

      it "rejects something that cannot be called" do
        e = assert_raises(ArgumentError) { slot << :not_callable }
        assert_includes e.message, "expected a callable"
      end
    end

    describe "fire" do
      it "snapshots, so a listener added during the fire runs on the next one" do
        runs = []
        list = slot
        list << -> { list << -> { runs << :newcomer } }
        list.fire(event)
        assert_empty runs
        list.fire(event)
        assert_equal [:newcomer], runs
      end

      it "snapshots, so a listener removed during the fire still runs this time" do
        runs = []
        victim = -> { runs << :victim }
        list = slot
        list << -> { list.remove(victim) } << victim
        list.fire(event)
        assert_equal [:victim], runs
        list.fire(event)
        assert_equal [:victim], runs
      end

      it "aborts the fire and propagates when a listener raises" do
        reached = false
        list = slot
        list << -> { raise Error, "boom" } << -> { reached = true }
        e = assert_raises(Error) { list.fire(event) }
        assert_equal "boom", e.message
        refute reached
      end
    end

    describe "the transition block" do
      it "is called with true only when the list stops being empty" do
        claims = []
        list = slot { |claimed| claims << claimed }
        list << -> {}
        list << -> {}
        assert_equal [true], claims
      end

      it "is called with false only when the list becomes empty again" do
        claims = []
        a = -> {}
        b = -> {}
        list = slot { |claimed| claims << claimed }
        list << a << b
        list.remove(a)
        assert_equal [true], claims
        list.remove(b)
        assert_equal [true, false], claims
      end

      it "is not called for a removal that was not there" do
        claims = []
        list = slot { |claimed| claims << claimed }
        list.remove(-> {})
        assert_empty claims
      end
    end

    describe Listeners::Declare do
      def owner_class
        Class.new do
          extend Listeners::Declare

          listener :on_ping
        end
      end

      it "returns the name" do
        name = nil
        Class.new do
          extend Listeners::Declare
          name = listener :on_ping
        end
        assert_equal :on_ping, name
      end

      it "rejects a name without the on_ prefix, at load time" do
        e = assert_raises(Error) do
          Class.new do
            extend Listeners::Declare
            listener :ping
          end
        end
        assert_includes e.message, "on_ping"
      end

      it "reads as the list when called without a block" do
        assert_instance_of Listeners, owner_class.new.on_ping
      end

      it "registers a block and returns the Proc, so a block can be removed" do
        owner = owner_class.new
        cb = owner.on_ping { :pinged }
        assert_instance_of Proc, cb
        assert owner.on_ping.include?(cb)
        assert owner.on_ping.remove(cb)
      end

      it "builds the list lazily but keeps the same one across reads" do
        owner = owner_class.new
        assert_same owner.on_ping, owner.on_ping
      end

      it "gives each instance its own list" do
        klass = owner_class
        one = klass.new
        two = klass.new
        one.on_ping { :pinged }
        assert_equal 1, one.on_ping.size
        assert_equal 0, two.on_ping.size
      end

      it "works when extended from a module and included into a class" do
        mixin = Module.new do
          extend Listeners::Declare

          listener :on_mixed
        end
        owner = Class.new { include mixin }.new
        owner.on_mixed { :ok }
        assert_equal 1, owner.on_mixed.size
      end

      it "reaches subclasses, since they inherit the singleton method" do
        base = Class.new { extend Listeners::Declare }
        sub = Class.new(base) { listener :on_sub }
        owner = sub.new
        owner.on_sub { :ok }
        assert_equal 1, owner.on_sub.size
      end

      it "runs the transition block on the owning instance" do
        klass = Class.new do
          extend Listeners::Declare

          attr_reader :claims

          def initialize = (@claims = [])

          listener(:on_ping) { |claimed| @claims << claimed }
        end
        owner = klass.new
        cb = owner.on_ping { :pinged }
        assert_equal [true], owner.claims
        owner.on_ping.remove(cb)
        assert_equal [true, false], owner.claims
      end

      it "names the slot in an arity error raised through the reader" do
        e = assert_raises(ArgumentError) { owner_class.new.on_ping << ->(_a, _b) {} }
        assert_includes e.message, "on_ping"
      end
    end
  end
end
