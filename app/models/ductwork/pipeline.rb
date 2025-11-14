# frozen_string_literal: true

module Ductwork
  class Pipeline < Ductwork::Record
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

      def trigger(*args)
        if pipeline_definition.nil?
          raise DefinitionError, "Pipeline must be defined before triggering"
        end

        step_klass = pipeline_definition.dig(:nodes, 0)
        definition = JSON.dump(pipeline_definition)

        Record.transaction do
          pipeline = create!(
            klass: name.to_s,
            status: :in_progress,
            definition: definition,
            definition_sha1: Digest::SHA1.hexdigest(definition),
            triggered_at: Time.current,
            last_advanced_at: Time.current
          )
          step = pipeline.steps.create!(
            klass: step_klass,
            status: :in_progress,
            step_type: :start,
            started_at: Time.current
          )
          Ductwork::Job.enqueue(step, *args)

          pipeline
        end
      end
    end

    def advance! # rubocop:todo Metrics
      parsed_definition = JSON.parse(definition).with_indifferent_access
      step = steps.advancing.take
      edge = if step.present?
               parsed_definition.dig(:edges, step.klass, 0)
             end

      Ductwork::Record.transaction do # rubocop:todo Metrics/BlockLength
        steps.advancing.update!(status: :completed, completed_at: Time.current)

        if edge.nil?
          if steps.where(status: %w[in_progress pending]).none?
            update!(status: :completed, completed_at: Time.current)
          end
        else
          # NOTE: "chain" is used by ActiveRecord so we have to call
          # this enum value "default" :sad:
          step_type = edge[:type] == "chain" ? "default" : edge[:type]

          if step_type.in?(%w[default divide])
            edge[:to].each do |klass|
              next_step = steps.create!(
                klass: klass,
                status: :in_progress,
                step_type: step_type,
                started_at: Time.current
              )
              Ductwork::Job.enqueue(next_step, step.job.return_value)
            end
          elsif step_type == "combine"
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
          elsif step_type == "expand"
            step.job.return_value.each do |input_arg|
              create_step_and_enqueue_job(
                klass: edge[:to].sole,
                step_type: step_type,
                input_arg: input_arg
              )
            end
          elsif step_type == "collapse"
            if steps.not_completed.where(klass: step.klass).none?
              input_arg = Job.where(
                step: steps.completed.where(klass: step.klass)
              ).map(&:return_value)
              create_step_and_enqueue_job(
                klass: edge[:to].sole,
                step_type: step_type,
                input_arg: input_arg
              )
            else
              logger.debug(msg: "Not all expanded steps have completed", role: :pipeline_advancer)
            end
          else
            logger.error("Invalid step type? This is wrong lol", role: :pipeline_advancer)
          end
        end
      end
    end

    private

    def logger
      Ductwork.configuration.logger
    end

    def create_step_and_enqueue_job(klass:, step_type:, input_arg:)
      status = :in_progress
      started_at = Time.current
      next_step = steps.create!(klass:, status:, step_type:, started_at:)
      Ductwork::Job.enqueue(next_step, input_arg)
    end
  end
end
