# frozen_string_literal: true

module Tuile
  class FormSyncer
    # What {Buffered#write!} raises when the write was refused — bad
    # data rather than framework misuse, as {StyledString::ParseError} is.
    #
    #   syncer.write!(person)
    # rescue FormSyncer::ValidationError => e
    #   e.failures   # => {name: [#<data ValidationFailure message="Name is required" …>]}
    class ValidationError < Error
      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] the frozen
      #   verdict map, {FormSyncer#last_validation} at the time of the raise.
      attr_reader :failures

      # @param failures [Hash{Symbol, nil => Array<ValidationFailure>}]
      def initialize(failures)
        @failures = failures
        super(failures.values.flatten.map(&:message).join("; "))
      end
    end
  end
end
