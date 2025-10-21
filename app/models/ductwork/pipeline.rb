# frozen_string_literal: true

module Ductwork
  class Pipeline < Ductwork::Record
    has_many :steps, class_name: "Ductwork::Step", foreign_key: "pipeline_id", dependent: :destroy

    validates :klass, presence: true
    validates :definition, presence: true
    validates :definition_sha1, presence: true
    validates :status, presence: true
    validates :triggered_at, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         completed: "completed"

    def self.inherited(subclass)
      super

      subclass.class_eval do
        default_scope { where(klass: name.to_s) }
      end
    end

    class DefinitionError < StandardError; end

    class << self
      attr_reader :pipeline_definition

      def define(&block)
        if !block_given?
          raise DefinitionError, "Definition block must be given"
        end

        if pipeline_definition
          raise DefinitionError, "Pipeline has already been defined"
        end

        builder = DefinitionBuilder.new

        block.call(builder)

        @pipeline_definition = builder.complete

        Ductwork.pipelines << name.to_s
      end

      # NOTE: will eventually refactor this method to fix the style violations
      def trigger(*args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        if pipeline_definition.nil?
          raise DefinitionError, "Pipeline must be defined before triggering"
        end

        pipeline = nil
        step_definition = pipeline_definition.branch.steps.first

        Record.transaction do
          pipeline = create!(
            klass: name.to_s,
            status: :in_progress,
            definition: pipeline_definition.to_json,
            definition_sha1: Digest::SHA1.hexdigest(pipeline_definition.to_json),
            triggered_at: Time.current
          )
          step = pipeline.steps.create!(
            klass: step_definition.klass,
            status: :in_progress,
            step_type: :start,
            started_at: Time.current
          )
          job = step.create_job!(
            klass: step_definition.klass,
            started_at: Time.current,
            input_args: JSON.dump(args)
          )
          execution = job.executions.create!(
            started_at: Time.current
          )
          execution.create_availability!(
            started_at: Time.current,
            completed: false
          )
        end

        pipeline
      end
    end
  end
end
