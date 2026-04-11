# frozen_string_literal: true

module Ductwork
  class Pipeline < Ductwork::Record # rubocop:todo Metrics/ClassLength
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
    class ReviveError < StandardError; end

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

    def revive!(duplicate_context: false)
      if !halted?
        raise ReviveError, "Cannot revive #{status} pipeline"
      end

      last_run = runs.order(started_at: :desc).first

      if last_run.blank?
        raise ReviveError, "Cannot revive pipeline without previous run"
      end

      now = Time.current
      new_run = last_run.dup
      new_run.triggered_at = now
      new_run.started_at = now
      new_run.status = "in_progress"

      Ductwork::Record.transaction do
        new_run.save!
        duplicate_successful_branches_and_steps(new_run, last_run, now)
        duplicate_halted_branches_and_steps(new_run, last_run, now)
        conditionally_duplicate_context(last_run, new_run, now, duplicate_context)
        in_progress!
      end

      self
    end

    private

    def duplicate_successful_branches_and_steps(new_run, last_run, now)
      status = %i[advancing waiting completed]

      last_run.branches.where(status:).find_each do |branch|
        new_branch = branch.dup
        new_branch.run = new_run
        new_branch.started_at = now
        new_branch.completed_at = now

        new_branch.save!

        branch.steps.where(status:).find_each do |step|
          new_step = step.dup
          new_step.source_step = step
          new_step.branch = new_branch
          new_step.run = new_run
          new_step.started_at = now
          new_step.completed_at = now

          new_step.save!
        end
      end
    end

    def duplicate_halted_branches_and_steps(new_run, last_run, now) # rubocop:todo Metrics/AbcSize
      status = %i[advancing waiting completed]

      last_run.branches.where(status: :halted).find_each do |branch| # rubocop:todo Metrics/BlockLength
        new_branch = branch.dup
        new_branch.run = new_run
        new_branch.status = "in_progress"
        new_branch.started_at = now
        new_branch.completed_at = nil
        new_branch.last_advanced_at = now
        new_branch.save!

        branch.steps.where(status:).find_each do |step|
          new_step = step.dup
          new_step.source_step = step
          new_step.branch = new_branch
          new_step.run = new_run
          new_step.started_at = now
          new_step.completed_at = now

          new_step.save!
        end

        failed_step = branch.steps.find_by(status: :failed)

        if failed_step.present?
          step = new_branch.steps.create!(
            run: new_run,
            node: failed_step.node,
            klass: failed_step.klass,
            status: :in_progress,
            to_transition: failed_step.to_transition,
            started_at: now
          )
          Ductwork::Job.enqueue(step)
        end
      end
    end

    def conditionally_duplicate_context(last_run, new_run, now, duplicate_context)
      if duplicate_context
        last_run.tuples.find_each do |tuple|
          new_tuple = tuple.dup
          new_tuple.run = new_run
          new_tuple.first_set_at = now
          new_tuple.last_set_at = now

          new_tuple.save!
        end
      end
    end
  end
end
