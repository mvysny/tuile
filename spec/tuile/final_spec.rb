# frozen_string_literal: true

module Tuile
  RSpec.describe Final do
    # A throwaway class hierarchy per example — Final memoizes verified
    # subclasses on the extending class, so sharing one would leak between them.
    def base_class
      base = Class.new do
        extend Final

        final attr_reader :locked

        final def touch = :base
      end
      base.define_method(:initialize) { base.verify_final!(self.class) }
      base
    end

    it "admits a subclass that overrides nothing final" do
      base = base_class
      Class.new(base) { def other = :fine }.new
    end

    it "admits the marking class itself" do
      base_class.new
    end

    it "rejects an override arriving through a def" do
      base = base_class
      e = assert_raises(Error) { Class.new(base) { def touch = :mine }.new }
      assert_includes e.message, "touch"
      assert_includes e.message, "may not be redefined"
    end

    it "rejects an override of a final attr_reader" do
      base = base_class
      e = assert_raises(Error) { Class.new(base) { def locked = :mine }.new }
      assert_includes e.message, "locked"
    end

    it "rejects an override arriving through an included module" do
      base = base_class
      sneaky = Module.new { def touch = :mine }
      e = assert_raises(Error) { Class.new(base) { include sneaky }.new }
      assert_includes e.message, "touch"
    end

    it "rejects an override arriving through a prepend" do
      base = base_class
      sneaky = Module.new { def touch = :mine }
      e = assert_raises(Error) { Class.new(base) { prepend sneaky }.new }
      assert_includes e.message, "touch"
    end

    it "names every offending method at once" do
      base = base_class
      klass = Class.new(base) do
        def touch = :mine
        def locked = :mine
      end
      e = assert_raises(Error) { klass.new }
      assert_includes e.message, "locked, touch"
    end

    it "points at each offender's rdoc" do
      base = base_class
      e = assert_raises(Error) { Class.new(base) { def touch = :mine }.new }
      assert_includes e.message, "#{base}#touch"
    end

    describe "#final" do
      it "hands back a bare Symbol for one name, the list for several" do
        probe = Class.new { extend Final }
        assert_equal :a, probe.final(:a)
        assert_equal %i[b c], probe.final(:b, :c)
      end

      it "flattens what attr_reader hands back, and marks every name" do
        probe = Class.new do
          extend Final
          final attr_reader :a, :b
        end
        assert_equal %i[a b], probe.final_methods
      end

      it "reports no final methods on a class that marks none" do
        assert_equal [], Class.new { extend Final }.final_methods
      end
    end

    describe "#verify_final!" do
      it "memoizes, so a second instantiation costs one lookup" do
        base = base_class
        sub = Class.new(base)
        sub.new
        # The override lands *after* the class was verified: the memo is the
        # only reason this is admitted, which is what proves it memoizes.
        sub.define_method(:touch) { :mine }
        sub.new
      end
    end
  end
end
