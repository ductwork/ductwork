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

        Ductwork.logger.info(
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
        if edges.nil? || edges.values.all?(&:empty?)
          conditionally_complete_pipeline(advancing)
        else
          advance_to_next_steps_by_type(edges, advancing)
        end
      end
    end

    def parsed_definition
      @parsed_definition ||= JSON.parse(definition).with_indifferent_access
    end

    private

    def create_step_and_enqueue_job(klass:, step_type:, input_arg:)
      status = :in_progress
      started_at = Time.current
      next_step = steps.create!(klass:, status:, step_type:, started_at:)
      Ductwork::Job.enqueue(next_step, input_arg)
    end

    def conditionally_complete_pipeline(advancing)
      advancing.update!(status: :completed, completed_at: Time.current)

      if steps.where(status: %w[in_progress pending]).none?
        update!(status: :completed, completed_at: Time.current)

        Ductwork.logger.info(
          msg: "Pipeline completed",
          pipeline_id: id,
          role: :pipeline_advancer
        )
      end
    end

    def advance_to_next_steps_by_type(edges, advancing)
      if edges.all? { |_, v| v.dig(-1, :type) == "combine" }
        conditionally_combine_next_steps(edges, advancing)
      else
        edges.each do |step_klass, step_edges|
          edge = step_edges[-1]
          # NOTE: "chain" is used by ActiveRecord so we have to call
          # this enum value "default" :sad:
          step_type = edge[:type] == "chain" ? "default" : edge[:type]

          if step_type == "collapse"
            conditionally_collapse_next_steps(step_klass, edge, advancing)
          else
            advance_non_merging_steps(step_klass, edges, advancing)
          end
        end
      end
      advancing.update!(status: :completed, completed_at: Time.current)
      log_pipeline_advanced(edges)
    end

    def advance_non_merging_steps(step_klass, edges, advancing)
      advancing.where(klass: step_klass).find_each do |step|
        edge = edges.dig(step.klass, -1)
        # NOTE: "chain" is used by ActiveRecord so we have to call
        # this enum value "default" :sad:
        step_type = edge[:type] == "chain" ? "default" : edge[:type]

        if step_type.in?(%w[default divide])
          advance_to_next_steps(step_type, advancing, edge)
        elsif step_type == "expand"
          expand_to_next_steps(step_type, advancing, edge)
        else
          Ductwork.logger.error(
            msg: "Invalid step type",
            step_type: step_type,
            pipeline_id: id,
            role: :pipeline_advancer
          )
        end
      end
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

    def conditionally_combine_next_steps(edges, advancing)
      if steps.where(status: %w[pending in_progress], klass: edges.keys).none?
        combine_next_steps(edges, advancing)
      else
        Ductwork.logger.debug(
          msg: "Not all divided steps have completed; not combining",
          pipeline_id: id,
          role: :pipeline_advancer
        )
      end
    end

    def combine_next_steps(edges, advancing)
      klass = edges.values.sample.dig(-1, :to).sole
      step_type = "combine"
      groups = advancing
               .group(:klass)
               .count
               .keys
               .map { |k| advancing.where(klass: k) }

      groups.first.zip(*groups[1..]).each do |group|
        input_arg = Ductwork::Job
                    .where(step_id: group.map(&:id))
                    .map(&:return_value)
        create_step_and_enqueue_job(klass:, step_type:, input_arg:)
      end
    end

    def expand_to_next_steps(step_type, advancing, edge)
      Array(advancing.take.job.return_value).each do |input_arg|
        create_step_and_enqueue_job(
          klass: edge[:to].sole,
          step_type: step_type,
          input_arg: input_arg
        )
      end
    end

    def conditionally_collapse_next_steps(step_klass, edge, advancing)
      if steps.where(status: %w[pending in_progress], klass: step_klass).none?
        collapse_next_steps(edge[:to].sole, advancing)
      else
        Ductwork.logger.debug(
          msg: "Not all expanded steps have completed; not collapsing",
          pipeline_id: id,
          role: :pipeline_advancer
        )
      end
    end

    def collapse_next_steps(klass, advancing)
      step_type = "collapse"
      input_arg = []

      # NOTE: because of expanding based on return values, there
      # could be A LOT of jobs so we want to use batch methods
      # to avoid creating too many in-memory objects
      Ductwork::Job.where(step_id: advancing.ids).find_each do |job|
        input_arg << job.return_value
      end

      create_step_and_enqueue_job(klass:, step_type:, input_arg:)
    end

    def log_pipeline_advanced(edges)
      Ductwork.logger.info(
        msg: "Pipeline advanced",
        pipeline_id: id,
        transitions: edges.map { |_, v| v.dig(-1, :type) },
        role: :pipeline_advancer
      )
    end
  end
end
