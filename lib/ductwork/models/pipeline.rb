# frozen_string_literal: true

module Ductwork
  class Pipeline < Ductwork::Record # rubocop:todo Metrics/ClassLength
    has_many :steps, class_name: "Ductwork::Step", foreign_key: "pipeline_id", dependent: :destroy
    has_many :tuples, class_name: "Ductwork::Tuple", foreign_key: "pipeline_id", dependent: :destroy

    validates :klass, presence: true
    validates :definition, presence: true
    validates :definition_sha1, presence: true
    validates :status, presence: true
    validates :started_at, presence: true
    validates :triggered_at, presence: true
    validates :last_advanced_at, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         waiting: "waiting",
         advancing: "advancing",
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

        node = pipeline_definition.dig(:nodes, 0)
        klass = pipeline_definition.dig(:edges, node, :klass)
        definition = JSON.dump(pipeline_definition)

        pipeline = Record.transaction do
          p = create!(
            klass: name.to_s,
            status: :in_progress,
            definition: definition,
            definition_sha1: Digest::SHA1.hexdigest(definition),
            triggered_at: Time.current,
            started_at: Time.current,
            last_advanced_at: Time.current
          )
          step = p.steps.create!(
            node: node,
            klass: klass,
            status: :in_progress,
            to_transition: :start,
            started_at: Time.current
          )
          Ductwork::Job.enqueue(step, *args)

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
      # NOTE: if we've expanded the pipeline there could be a lot of
      # advancing records which may cause memory issues. something to
      # watch out for here and maybe add in config to use AR relation
      # at certain counts or even memory limits.
      advancing_steps = steps.advancing.pluck(:id, :node, :klass)
      advancing_ids = advancing_steps.map(&:first)
      edges = find_edges(advancing_steps)

      Ductwork::Record.transaction do
        if edges.nil? || edges.all? { |_, attrs| attrs[:to].blank? }
          conditionally_complete_pipeline(advancing_ids)
        else
          advance_to_next_steps_by_type(edges, advancing_ids)
        end
      end
    end

    def parsed_definition
      @parsed_definition ||= JSON.parse(definition).with_indifferent_access
    end

    def complete!
      update!(status: :completed, completed_at: Time.current)

      Ductwork.logger.info(
        msg: "Pipeline completed",
        pipeline_id: id,
        role: :pipeline_advancer
      )
    end

    def halt!
      update!(status: :halted, halted_at: Time.current)

      Ductwork.logger.info(
        msg: "Pipeline halted",
        pipeline_id: id,
        pipeline_klass: klass
      )
    end

    private

    def create_step_and_enqueue_job(edge:, input_arg:, node: nil)
      status = :in_progress
      started_at = Time.current
      # NOTE: "chain" is used by ActiveRecord so we have to call
      # this enum value "default" :sad:
      to_transition = edge[:type] == "chain" ? "default" : edge[:type]
      node ||= edge[:to].sole
      klass = parsed_definition.dig(:edges, node, :klass)

      next_step = steps.create!(node:, klass:, status:, to_transition:, started_at:)
      Ductwork::Job.enqueue(next_step, input_arg)
    end

    def find_edges(advancing_steps)
      if advancing_steps.any?
        nodes = advancing_steps.map(&:second)

        parsed_definition.fetch(:edges, {}).select { |k| k.in?(nodes) }
      end
    end

    def conditionally_complete_pipeline(advancing_ids)
      steps
        .where(id: advancing_ids)
        .update_all(status: :completed, completed_at: Time.current)

      remaining = steps
                  .where(status: %w[in_progress pending advancing])
                  .where.not(id: advancing_ids)
                  .exists?

      if !remaining
        complete!
      end
    end

    def advance_to_next_steps_by_type(edges, advancing_ids)
      steps.where(id: advancing_ids).update_all(status: :completed, completed_at: Time.current)

      case edges
      in _ if edges.all? { |_, attrs| attrs[:type] == "combine" }
        conditionally_combine_next_steps(edges, advancing_ids)
      else
        edges.each do |node, attrs|
          case attrs[:type]
          in "collapse"
            conditionally_collapse_next_steps(node, attrs, advancing_ids)
          else
            advance_non_merging_steps(attrs, advancing_ids)
          end
        end
      end
      log_pipeline_advanced(edges)
    end

    def advance_non_merging_steps(edge, advancing_ids)
      to_transition = edge[:type]
      klass = edge[:klass]

      steps.where(id: advancing_ids, klass: klass).find_each do |step|
        case to_transition
        in "chain" | "divide"
          advance_to_next_steps(step.id, edge)
        in "expand"
          expand_to_next_steps(step.id, edge)
        else
          Ductwork.logger.error(
            msg: "Invalid To Transition",
            to_transition: to_transition,
            pipeline_id: id,
            role: :pipeline_advancer
          )
        end
      end
    end

    def advance_to_next_steps(step_id, edge)
      too_many = edge[:to].tally.any? do |to_klass, count|
        depth = Ductwork
                .configuration
                .steps_max_depth(pipeline: klass, step: to_klass)

        depth != -1 && count > depth
      end

      if too_many
        halt!
      else
        edge[:to].each do |node|
          input_arg = Ductwork::Job.find_by(step_id:).return_value
          create_step_and_enqueue_job(edge:, input_arg:, node:)
        end
      end
    end

    def conditionally_combine_next_steps(edges, advancing_ids)
      if steps.where(status: %w[pending in_progress], node: edges.keys).none?
        combine_next_steps(edges, advancing_ids)
      else
        Ductwork.logger.debug(
          msg: "Not all divided steps have completed; not combining",
          pipeline_id: id,
          role: :pipeline_advancer
        )
      end
    end

    def combine_next_steps(edges, advancing_ids)
      edge = edges.values.sample
      groups = steps
               .where(id: advancing_ids)
               .group(:node)
               .count
               .keys
               .map { |node| steps.where(id: advancing_ids).where(node:) }

      groups.first.zip(*groups[1..]).each do |group|
        input_arg = Ductwork::Job
                    .where(step_id: group.map(&:id))
                    .map(&:return_value)
        create_step_and_enqueue_job(edge:, input_arg:)
      end
    end

    def expand_to_next_steps(step_id, edge)
      next_klass = edge[:to].sole
      return_value = Ductwork::Job
                     .find_by(step_id:)
                     .return_value
      max_depth = Ductwork.configuration.steps_max_depth(pipeline: klass, step: next_klass)

      if max_depth != -1 && return_value.count > max_depth
        halt!
      else
        # TODO: Brainstorm on using `insert_all` instead of iterating.
        # Performance is bad when the return value has a lot of elements
        # and we create a step and job individually
        Array(return_value).each do |input_arg|
          create_step_and_enqueue_job(edge:, input_arg:)
        end
      end
    end

    def conditionally_collapse_next_steps(node, edge, advancing_ids)
      if steps.where(status: %w[pending in_progress], node: node).none?
        collapse_next_steps(edge, advancing_ids)
      else
        Ductwork.logger.debug(
          msg: "Not all expanded steps have completed; not collapsing",
          pipeline_id: id,
          role: :pipeline_advancer
        )
      end
    end

    def collapse_next_steps(edge, advancing_ids)
      input_arg = []

      Ductwork::Job.where(step_id: advancing_ids).find_each do |job|
        input_arg << job.return_value
      end

      create_step_and_enqueue_job(edge:, input_arg:)
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
