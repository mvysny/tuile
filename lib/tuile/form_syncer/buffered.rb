# frozen_string_literal: true

module Tuile
  class FormSyncer
    # Binds fields to a model and writes them back only on Save, and only when
    # every validator passes — the form syncer for a form in an OK/Cancel overlay, where
    # Cancel is free because nothing reached the model:
    #
    #   syncer = FormSyncer::Buffered.new
    #   syncer.bind(name_field, :name).required("Name is required")
    #   syncer.bind(age_field, :age).validate { |v| "Must be positive" unless v.positive? }
    #   syncer.read(person)
    #
    #   save.on_click do
    #     if syncer.write?(person)
    #       overlay.close
    #     else
    #       messages = syncer.last_validation.values.flatten.map(&:message)
    #       Component::ConfirmDialog.alert("Cannot save", messages.join("\n"))
    #     end
    #   end
    #
    # A field's verdict shows once the user has edited it, and on every field
    # at once after {#write?} or {#validate}; {#read} shows none, so a blank
    # "New person" form doesn't open red. The chain, the empty/`nil` policy and
    # how the model validators use the model as scratch space are {FormSyncer}'s.
    #
    # A verdict updates when its field announces an edit: for a string or
    # number field that is when the user leaves it or presses ENTER, the
    # {Component::HasValueChangeMode#value_change_mode} default — set a field
    # `:eager` for a verdict that follows every keystroke.
    #
    # == Implementation details
    # Each edit runs its own pipeline only; the model validators run in
    # {#read}, {#validate} and {#write?} alone, so a model validation failure
    # stays in {#last_validation} after the edit that fixes it, until the next
    # of those. An edit is a
    # `from_user?` value change: the form syncer's own writes and an app's
    # {Component::HasValue#value=} are not the user's, and run nothing.
    class Buffered < FormSyncer
      def initialize
        super { |pipeline, edit| edited(pipeline, edit) }
        @_model = nil
        @_changed = Set.new
      end

      # Shows `model` in the fields and remembers it for {#validate}; a `nil`
      # model clears them. Recomputes {#last_validation}, showing no verdict, and
      # writes nothing — the model validators see the model as it is.
      # @param model [Object, nil]
      # @return [void]
      # @raise [ArgumentError] when a converter's `to_value` rejects the stored value.
      def read(model)
        @_model = model
        @_changed.clear
        @_engine.populate(model)
        @_engine.run(@_engine.pipelines, model:, write: [], keep: false, show: [])
        nil
      end

      # Runs every pipeline and — against the model {#read} was handed — every
      # model validator, showing every verdict, and leaves the model as it was.
      # @return [Hash{Symbol, nil => Array<ValidationFailure>}] {#last_validation}.
      def validate
        all = @_engine.pipelines
        @_engine.run(all, model: @_model, write: all, keep: false, show: :all)
        last_validation
      end

      # Writes the fields into `model` if every validator passes, showing
      # every verdict either way; on a failure `model` is left as it was.
      # @param model [Object] usually the one {#read} was handed, but need not be.
      # @return [Boolean] whether the write happened; see {#last_validation} when not.
      def write?(model)
        raise ArgumentError, "write? needs a model" if model.nil?

        all = @_engine.pipelines
        written = @_engine.run(all, model:, write: all, keep: true, show: :all)
        @_changed.clear if written
        written
      end

      # {#write?}, raising instead of answering `false`.
      # @param model [Object]
      # @return [void]
      # @raise [FormSyncer::ValidationError] carrying {#last_validation}.
      def write!(model)
        raise ValidationError, last_validation unless write?(model)
      end

      # @return [Boolean] whether the user edited a field since {#read} or the
      #   last successful {#write?} — edited, not differing, so a `""` shown for
      #   a `nil` attribute is no change. An edit counts once its field
      #   announces it; a Save the user reaches takes focus, which announces
      #   the field being left.
      def changed? = !@_changed.empty?

      private

      # @param pipeline [FormSyncer::Pipeline]
      # @param edit [Boolean]
      # @return [void]
      def edited(pipeline, edit)
        @_changed << pipeline.attr if edit
        @_engine.run_fields([pipeline])
        @_engine.reveal([pipeline.attr])
      end
    end
  end
end
