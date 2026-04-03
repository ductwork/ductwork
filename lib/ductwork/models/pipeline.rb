# frozen_string_literal: true

module Ductwork
  class Pipeline < Ductwork::Record
    has_many :runs,
             class_name: "Ductwork::Run",
             foreign_key: "pipeline_id",
             dependent: :destroy

    validates :klass, presence: true
    validates :status, presence: true

    enum :status,
         pending: "pending",
         in_progress: "in_progress",
         waiting: "waiting",
         advancing: "advancing",
         halted: "halted",
         dampened: "dampened",
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

      def trigger(*args) # rubocop:todo Metrics
        if pipeline_definition.nil?
          raise DefinitionError, "Pipeline must be defined before triggering"
        end

        now = Time.current
        node = pipeline_definition.dig(:nodes, 0)
        klass = pipeline_definition.dig(:edges, node, :klass)
        definition = JSON.dump(pipeline_definition)

        pipeline = Record.transaction do # rubocop:todo Metrics/BlockLength
          p = create!(
            klass: name.to_s,
            status: :in_progress
          )
          run = p.runs.create!(
            pipeline_klass: name.to_s,
            status: :in_progress,
            definition: definition,
            definition_sha1: Digest::SHA1.hexdigest(definition),
            triggered_at: now,
            started_at: now
          )
          branch = run.branches.create!(
            pipeline_klass: name.to_s,
            status: :in_progress,
            started_at: now,
            last_advanced_at: now
          )
          step = branch.steps.create!(
            run: run,
            node: node,
            klass: klass,
            status: :in_progress,
            to_transition: :start,
            started_at: now
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

    def current_run
      runs.in_progress.sole
    end

    def complete!
      Ductwork::Record.transaction do
        completed!
        current_run.update!(status: :completed, completed_at: Time.current)
      end

      Ductwork.logger.info(
        msg: "Pipeline completed",
        pipeline_id: id,
        role: :pipeline_advancer
      )
    end

    def halt!
      Ductwork::Record.transaction do
        halted!
        current_run.update!(status: :halted, halted_at: Time.current)
      end

      Ductwork.logger.info(
        msg: "Pipeline halted",
        pipeline_id: id,
        pipeline_klass: klass
      )
    end
  end
end
