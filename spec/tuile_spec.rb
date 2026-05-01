# frozen_string_literal: true

RSpec.describe Tuile do
  it "has a version number" do
    refute_nil Tuile::VERSION
  end

  describe ".logger" do
    around do |example|
      saved = Tuile.instance_variable_get(:@logger)
      Tuile.instance_variable_set(:@logger, nil)
      example.run
    ensure
      Tuile.instance_variable_set(:@logger, saved)
    end

    it "lazily defaults to a null Logger" do
      logger = Tuile.logger
      assert_kind_of Logger, logger
      assert_same logger, Tuile.logger
    end

    it "honors an explicit assignment" do
      custom = Logger.new(IO::NULL)
      Tuile.logger = custom
      assert_same custom, Tuile.logger
    end
  end
end
