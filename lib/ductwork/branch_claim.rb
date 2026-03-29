# frozen_string_literal: true

module Ductwork
  class BranchClaim
    attr_reader :transition, :advancement

    def initialize(pipeline_klass)
      @pipeline_klass = pipeline_klass
      @claimed_for_advancing_at = nil
    end

    def latest
      id = find_candidate_branch_id

      return log_no_branches if id.blank?

      rows_updated = claim_and_setup_records(id)

      if rows_updated == 1
        Ductwork.wrap_with_app_executor do
          [Branch.find(id), transition, advancement]
        end
      else
        log_race_condition(id)
      end
    end

    private

    attr_reader :pipeline_klass, :claimed_for_advancing_at

    def find_candidate_branch_id
      Ductwork.wrap_with_app_executor do
        Ductwork::Branch
          .in_progress
          .where(pipeline_klass:, claimed_for_advancing_at:)
          .where(steps: Ductwork::Step.where(status: :advancing))
          .where.not(steps: Ductwork::Step.where.not(status: %w[advancing completed]))
          .order(:last_advanced_at)
          .limit(1)
          .pluck(:id)
          .first
      end
    end

    def claim_and_setup_records(id)
      now = Time.current

      Ductwork.wrap_with_app_executor do
        Ductwork::Record.transaction do
          rows_updated = Ductwork::Branch
                         .where(id:, claimed_for_advancing_at:)
                         .update_all(claimed_for_advancing_at: now, status: :advancing)

          if rows_updated == 1
            branch = Branch.find(id)
            @transition = find_or_create_transition(branch, now)
            @advancement = transition.advancements.create!(
              process: Ductwork::Process.current,
              started_at: now
            )
          end

          rows_updated
        end
      end
    end

    def find_or_create_transition(branch, now)
      existing = branch
                 .transitions
                 .where(completed_at: nil)
                 .order(started_at: :desc)
                 .limit(1)
                 .first

      if existing
        fail_abandoned_advancement(existing, now)
        existing
      else
        branch.transitions.create!(
          in_step: branch.latest_step,
          started_at: now
        )
      end
    end

    def fail_abandoned_advancement(transition, now)
      transition
        .advancements
        .where(completed_at: nil)
        .order(started_at: :desc)
        .limit(1)
        .first
        &.update!(
          completed_at: now,
          error_klass: "Ductwork::ProcessCrash",
          error_message: "Advancement was abandoned from a process crash"
        )
    end

    def log_no_branches
      Ductwork.logger.debug(
        msg: "No branches needs advancing",
        pipeline: pipeline_klass,
        role: :pipeline_advancer
      )

      nil
    end

    def log_race_condition(id)
      Ductwork.logger.debug(
        msg: "Did not claim branch, avoided race condition",
        branch_id: id,
        pipeline_klass: pipeline_klass,
        role: :pipeline_advancer
      )

      nil
    end
  end
end
