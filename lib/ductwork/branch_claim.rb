# frozen_string_literal: true

module Ductwork
  class BranchClaim
    attr_reader :transition, :advancement, :token

    def initialize(pipeline_klass)
      @pipeline_klass = pipeline_klass
      @claimed_for_advancing_at = nil
    end

    def latest
      # NOTE: an advancement must attach to a live process record so the reaper
      # can find and recover it if this process dies. `Process.current` is only
      # nil when our record was reaped for a stale heartbeat (e.g. host suspend)
      # and the runner has not re-adopted it yet — i.e. the system has already
      # declared this process dead. Claiming as a presumed-dead zombie would
      # create an advancement with a nil `process_id` that no reaper sweep can
      # reach, orphaning the branch. Skip this cycle instead; the runner
      # re-adopts within its heartbeat interval.
      process = Ductwork::Process.current

      return log_no_process if process.nil?

      id = find_candidate_branch_id

      return log_no_branches if id.blank?

      rows_updated = claim_and_setup_records(id, process)

      if rows_updated == 1
        Ductwork::Branch.find(id)
      else
        log_race_condition(id)
      end
    end

    private

    attr_reader :pipeline_klass, :claimed_for_advancing_at

    def find_candidate_branch_id
      Ductwork::Branch
        .in_progress
        .where(pipeline_klass:, claimed_for_advancing_at:)
        .where(steps: Ductwork::Step.where(status: %w[advancing failed]))
        .order(:last_advanced_at)
        .limit(1)
        .pluck(:id)
        .first
    end

    def claim_and_setup_records(id, process)
      now = Time.current
      @token = SecureRandom.uuid

      Ductwork::Record.transaction do
        rows_updated = Ductwork::Branch
                       .where(id:, claimed_for_advancing_at:)
                       .update_all(
                         claimed_for_advancing_at: now,
                         claim_token: token,
                         status: :advancing
                       )

        if rows_updated == 1
          branch = Branch.find(id)
          @transition = find_or_create_transition(branch, now)
          @advancement = transition.advancements.create!(
            process: process,
            started_at: now,
            crash_count: next_crash_count(transition)
          )
        end

        rows_updated
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

    # NOTE: each crash spawns a fresh advancement at re-claim, so the running
    # crash total lives on the advancement and carries forward (mirroring
    # `Ductwork::Execution#crash_count`). The prior advancement is read after
    # `find_or_create_transition` has already marked any abandoned in-flight
    # advancement as a crash, so both the reaper/thread-cleanup path and the
    # `fail_abandoned_advancement` path are reflected here. A fresh transition
    # starts at 0; a non-crash errored prior carries the total unchanged.
    def next_crash_count(transition)
      prior = transition.advancements.order(started_at: :desc).first
      base = prior&.crash_count || 0

      if prior&.crash?
        base + 1
      else
        base
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

    def log_no_process
      Ductwork.logger.debug(
        msg: "No live process record, skipping branch claim",
        pipeline: pipeline_klass,
        role: :pipeline_advancer
      )

      nil
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
