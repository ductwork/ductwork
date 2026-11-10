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

    DEFAULT_STEP_ORDER_PRECISION = 6
    private_constant :DEFAULT_STEP_ORDER_PRECISION

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

        now = Ductwork::DatabaseClock.now
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

      now = Ductwork::DatabaseClock.now
      new_run = last_run.dup
      new_run.triggered_at = now
      new_run.started_at = now
      new_run.status = "in_progress"
      new_run.on_halt_dispatched_at = nil

      Ductwork::Record.transaction do
        lock!
        new_run.save!
        duplicate_successful_branches_and_steps(new_run, last_run, now)
        duplicate_halted_branches_and_steps(new_run, last_run, now)
        conditionally_duplicate_context(last_run, new_run, now, duplicate_context)
        duplicate_all_branch_links(new_run, last_run)
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

        duplicate_succeeded_steps(branch.steps.where(status:), new_branch, new_run, now)
      end
    end

    def duplicate_halted_branches_and_steps(new_run, last_run, now)
      last_run.branches.where(status: :halted).find_each do |branch|
        new_branch = branch.dup
        new_branch.run = new_run
        new_branch.status = "in_progress"
        new_branch.started_at = now
        new_branch.completed_at = nil
        new_branch.last_advanced_at = now

        new_branch.save!
        revive_branch_steps(branch, new_branch, new_run, now)
      end
    end

    def revive_branch_steps(branch, new_branch, new_run, now)
      duplicate_prior_steps_as_completed(branch, new_branch, new_run, now)
      revive_latest_step(branch.latest_step, new_branch, new_run, now)
    end

    def revive_latest_step(latest_step, new_branch, new_run, now)
      if latest_step.failed?
        re_enqueue_failed_step(latest_step, new_branch, new_run, now)
      else
        re_advance_latest_step(latest_step, new_branch, new_run, now)
      end
    end

    def duplicate_prior_steps_as_completed(branch, new_branch, new_run, now)
      latest_step = branch.latest_step

      return if latest_step.blank?

      status = %i[advancing waiting completed]
      id = latest_step.id

      steps = branch.steps.where(status:).where.not(id:)

      duplicate_succeeded_steps(steps, new_branch, new_run, now, steps_after: 1)
    end

    def duplicate_succeeded_steps(steps, new_branch, new_run, now, steps_after: 0)
      ordered_steps = steps.includes(:job).order(:started_at, :id).to_a
      tick = step_order_tick

      ordered_steps.reverse_each.with_index(steps_after) do |step, ticks_back|
        started_at = now - (ticks_back * tick)

        duplicate_succeeded_step(step, new_branch, new_run, now, started_at)
      end
    end

    def step_order_tick
      precision = Ductwork::Step.columns_hash["started_at"].precision

      Rational(1, 10**(precision || DEFAULT_STEP_ORDER_PRECISION))
    end

    def duplicate_succeeded_step(step, new_branch, new_run, now, started_at)
      new_step = step.dup
      new_step.source_step = step
      new_step.branch = new_branch
      new_step.run = new_run
      new_step.started_at = started_at
      new_step.completed_at = now

      new_step.save!
      duplicate_job(step.job, new_step, now) if step.job.present?
    end

    def re_enqueue_failed_step(failed_step, new_branch, new_run, now)
      args = JSON.parse(failed_step.job.input_args).fetch("args")
      step = new_branch.steps.create!(
        run: new_run,
        source_step: failed_step,
        node: failed_step.node,
        klass: failed_step.klass,
        to_transition: failed_step.to_transition,
        status: :in_progress,
        started_at: now
      )
      Ductwork::Job.enqueue(step, *args)
    end

    def re_advance_latest_step(latest_step, new_branch, new_run, now)
      step = new_branch.steps.create!(
        run: new_run,
        source_step: latest_step,
        node: latest_step.node,
        klass: latest_step.klass,
        to_transition: latest_step.to_transition,
        status: :advancing,
        started_at: now
      )
      duplicate_job(latest_step.job, step, now)
    end

    def duplicate_job(job, new_step, now)
      new_job = job.dup
      new_job.step = new_step
      new_job.started_at = now
      new_job.completed_at = now
      new_job.save!
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

    def duplicate_all_branch_links(new_run, last_run)
      map = Ductwork::Step
            .where(branch_id: new_run.branches.select(:id))
            .where.not(source_step_id: nil)
            .joins("INNER JOIN ductwork_steps src ON src.id = ductwork_steps.source_step_id")
            .pluck("src.branch_id", "ductwork_steps.branch_id")
            .uniq
            .to_h
      old_branch_ids = last_run.branches.select(:id)

      Ductwork::BranchLink
        .where(parent_branch_id: old_branch_ids, child_branch_id: old_branch_ids)
        .find_each do |old_link|
          Ductwork::BranchLink.create!(
            parent_branch_id: map.fetch(old_link.parent_branch_id),
            child_branch_id: map.fetch(old_link.child_branch_id)
          )
        end
    end
  end
end
