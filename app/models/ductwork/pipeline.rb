# frozen_string_literal: true

module Ductwork
  class Pipeline < Ductwork::Record # rubocop:todo Metrics/ClassLength
    has_many :steps, class_name: "Ductwork::Step", foreign_key: "pipeline_id", dependent: :destroy

    validates :klass, presence: true
    validates :definition, presence: true
    validates :definition_sha1, presence: true
    validates :status, presence: true
    validates :triggered_at, presence: true
    validates :last_advanced_at, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         halted: "halted",
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

        builder = Ductwork::DSL::DefinitionBuilder.new

        block.call(builder)

        @pipeline_definition = builder.complete

        Ductwork.defined_pipelines << name.to_s
      end

      def trigger(args)
        if pipeline_definition.nil?
          raise DefinitionError, "Pipeline must be defined before triggering"
        end

        step_klass = pipeline_definition.dig(:nodes, 0)
        definition = JSON.dump(pipeline_definition)

        pipeline = Record.transaction do
          p = create!(
            klass: name.to_s,
            status: :in_progress,
            definition: definition,
            definition_sha1: Digest::SHA1.hexdigest(definition),
            triggered_at: Time.current,
            last_advanced_at: Time.current
          )
          step = p.steps.create!(
            klass: step_klass,
            status: :in_progress,
            step_type: :start,
            started_at: Time.current
          )
          Ductwork::Job.enqueue(step, args)

          p
        end

        Ductwork.configuration.logger.info(
          msg: "Pipeline triggered",
          pipeline_id: pipeline.id,
          role: :application
        )

        pipeline
      end
    end

    def advance!
      # NOTE: there could be A LOT of steps advancing for a single pipeline
      # so instead of loading everything into memory and using ruby collection
      # methods we make multiple queries. may need to revisist this once
      # we do extensive load testing
      advancing = steps.advancing
      edges = if advancing.exists?
                parsed_definition
                  .fetch(:edges, {})
                  .select { |k| k.in?(advancing.pluck(:klass)) }
              end

      Ductwork::Record.transaction do
        advancing.update!(status: :completed, completed_at: Time.current)

        if edges.nil? || edges.values.all?(&:empty?)
          conditionally_complete_pipeline
        else
          advance_to_next_steps_by_type(edges, advancing)
        end
      end
    end

    private

    def create_step_and_enqueue_job(klass:, step_type:, input_arg:)
      status = :in_progress
      started_at = Time.current
      next_step = steps.create!(klass:, status:, step_type:, started_at:)
      Ductwork::Job.enqueue(next_step, input_arg)
    end

    def parsed_definition
      @parsed_definition ||= JSON.parse(definition).with_indifferent_access
    end

    def conditionally_complete_pipeline
      if steps.where(status: %w[in_progress pending]).none?
        update!(status: :completed, completed_at: Time.current)

        Ductwork.configuration.logger.info(
          msg: "Pipeline completed",
          pipeline_id: id,
          role: :pipeline_advancer
        )
      end
    end

    def advance_to_next_steps_by_type(edges, advancing)
      # NOTE: "chain" is used by ActiveRecord so we have to call
      # this enum value "default" :sad:
      advancing.find_each do |step|
        edge = edges.dig(step.klass, -1)
        step_type = edge[:type] == "chain" ? "default" : edge[:type]

        if step_type.in?(%w[default divide])
          advance_to_next_steps(step_type, advancing, edge)
        elsif step_type == "combine"
          combine_next_steps(step_type, advancing, edge)
        elsif step_type == "expand"
          expand_to_next_steps(step_type, advancing, edge)
        elsif step_type == "collapse"
          collapse_next_steps(step_type, advancing, edge)
        else
          Ductwork.configuration.logger.error(
            msg: "Invalid step type",
            role: :pipeline_advancer
          )
        end
      end

      Ductwork.configuration.logger.info(
        msg: "Pipeline advanced",
        pipeline_id: id,
        transitions: edges.map { |_, v| v.dig(-1, :type) },
        role: :pipeline_advancer
      )
    end

    def advance_to_next_steps(step_type, advancing, edge)
      edge[:to].each do |to_klass|
        next_step = steps.create!(
          klass: to_klass,
          status: :in_progress,
          step_type: step_type,
          started_at: Time.current
        )
        Ductwork::Job.enqueue(next_step, advancing.take.job.return_value)
      end
    end

    def combine_next_steps(step_type, _advancing, edge)
      previous_klasses = parsed_definition[:edges].select do |_, v|
        v.dig(0, :to, 0) == edge[:to].sole && v.dig(0, :type) == "combine"
      end.keys

      if steps.not_completed.where(klass: previous_klasses).none?
        input_arg = Job.where(
          step: steps.completed.where(klass: previous_klasses)
        ).map(&:return_value)
        create_step_and_enqueue_job(
          klass: edge[:to].sole,
          step_type: step_type,
          input_arg: input_arg
        )
      end
    end

    def expand_to_next_steps(step_type, advancing, edge)
      advancing.take.job.return_value.each do |input_arg|
        create_step_and_enqueue_job(
          klass: edge[:to].sole,
          step_type: step_type,
          input_arg: input_arg
        )
      end
    end

    def collapse_next_steps(step_type, advancing, edge)
      klass = advancing.take.klass

      # FIXME: iunno, rethink these queries
      if steps.not_completed.where(klass:).none?
        input_arg = Job.where(
          step: steps.completed.where(klass:)
        ).map(&:return_value)
        create_step_and_enqueue_job(
          klass: edge[:to].sole,
          step_type: step_type,
          input_arg: input_arg
        )
      else
        Ductwork.configuration.logger.debug(
          msg: "Not all expanded steps have completed",
          role: :pipeline_advancer
        )
      end
    end
  end
end
