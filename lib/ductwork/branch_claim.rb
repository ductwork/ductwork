# frozen_string_literal: true

module Ductwork
  class BranchClaim
    attr_reader :transition, :advancement, :token

    MAX_CLAIM_ATTEMPTS = 3

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

      ids = find_candidate_branch_ids

      return log_no_branches if ids.blank?

      Ductwork::FaultInjection.checkpoint(:after_branch_candidate_select)

      claimed_id = claim_and_setup_records(ids, process)

      if claimed_id
        Ductwork::Branch.find(claimed_id)
      else
        log_lost_claim_races
      end
    rescue ActiveRecord::InvalidForeignKey => e
      # NOTE: our own `process` record was reaped (heartbeat-stale, destroyed)
      # between the nil-check above and `transition.advancements.create!`
      # inside `claim_and_setup_records`. The insert's FK check blocks on the
      # reaper's row lock and then fails once the parent is gone, rolling back
      # the whole claim transaction (branch + transition + advancement) --
      # nothing is left half-committed. Treat it like any other lost claim
      # race instead of letting it propagate and kill the advancer thread.
      log_process_reaped_mid_claim(e)
    end

    private

    attr_reader :pipeline_klass, :claimed_for_advancing_at, :attempted_branch_id

    def candidate_window_size
      @candidate_window_size ||= begin
        pipeline_advancer_count = Ductwork
                                  .configuration
                                  .pipeline_advancer_count(pipeline_klass)

        (pipeline_advancer_count * 4).clamp(20, 100)
      end
    end

    # NOTE: the single source of truth for "this branch has work to advance",
    # shared by the candidate `SELECT` and the claiming `UPDATE` so the two can
    # never drift. Without a `SELECT ... FOR UPDATE`, candidate selection and
    # claiming are separate statements, so the claim MUST re-assert every
    # predicate the selection relied on -- not just `claimed_for_advancing_at IS
    # NULL`. Between the two, the advancer that already owned this branch can
    # finish and `release!` it (back to `in_progress`, claim nulled), which
    # leaves the null check satisfied by a branch whose latest step is now a
    # freshly enqueued `in_progress` one. Claiming that would advance the branch
    # off a step whose job has not run yet -- routing on a nil return value and
    # minting a duplicate downstream step. The window is normally microseconds,
    # but the candidate `SELECT` scans the branch/step tables, so at scale
    # (~1M live branches) it stretches into the tens of milliseconds and the
    # race becomes routine. Sampling from a window rather than always taking
    # the single oldest row spreads advancers across distinct candidates, but
    # it also means an id can sit unattempted while earlier attempts in the
    # walk run -- so the ids reaching the claiming `UPDATE` are, if anything,
    # staler than before and the re-assertion matters more, not less.
    # Re-asserting the status keeps a `completed`/`halted` branch from being
    # resurrected the same way.
    def claimable_branches
      Ductwork::Branch
        .in_progress
        .where(pipeline_klass:, claimed_for_advancing_at:)
        .where(steps: Ductwork::Step.where(status: Ductwork::Step::ADVANCEABLE_STATUSES))
    end

    def find_candidate_branch_ids
      claimable_branches
        .order(:last_advanced_at)
        .limit(candidate_window_size)
        .pluck(:id)
        .sample(MAX_CLAIM_ATTEMPTS)
    end

    def claim_and_setup_records(ids, process)
      ids.each do |id|
        @attempted_branch_id = id
        claimed_id = attempt_claim(id, process)

        return claimed_id if claimed_id
      end

      nil
    end

    def attempt_claim(id, process)
      now = Time.current
      @token = SecureRandom.uuid

      Ductwork::Record.transaction do
        rows_updated = claimable_branches
                       .where(id:)
                       .update_all(
                         claimed_for_advancing_at: now,
                         claim_token: token,
                         status: :advancing
                       )

        next nil unless rows_updated == 1

        branch = Branch.find(id)
        @transition = find_or_create_transition(branch, now)
        Ductwork::FaultInjection.checkpoint(:before_advancement_create)
        @advancement = transition.advancements.create!(
          process: process,
          started_at: now,
          crash_count: next_crash_count(transition)
        )

        id
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

    def log_lost_claim_races
      Ductwork.logger.debug(
        msg: "Did not claim branch, lost races on all sampled IDs",
        pipeline_klass: pipeline_klass,
        role: :pipeline_advancer
      )

      nil
    end

    def log_process_reaped_mid_claim(error)
      Ductwork.logger.warn(
        msg: "Did not claim branch, our process record was reaped mid-claim",
        branch_id: attempted_branch_id,
        pipeline_klass: pipeline_klass,
        error_klass: error.class.to_s,
        error_message: error.message,
        role: :pipeline_advancer
      )

      nil
    end
  end
end
