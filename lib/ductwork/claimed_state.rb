# frozen_string_literal: true

module Ductwork
  # NOTE: normalizes the display state of a freshly claimed job, moving its
  # step, run, and pipeline to `in_progress`.
  #
  # The step row belongs to the one claim, but the run and pipeline rows are
  # shared by every step of the run, so a million-wide expand funnels every
  # concurrent claim through the same two rows. Each write is already
  # conditional and matches nothing once the run is under way, but a no-op
  # `UPDATE` is not free everywhere: PostgreSQL never locks a tuple that fails
  # the qualification, while InnoDB at REPEATABLE READ takes the exclusive lock
  # during the primary key lookup and only releases it on a non-matching row
  # under READ COMMITTED's semi-consistent read. On MySQL and Trilogy that left
  # every worker holding both shared rows for the rest of its claim
  # transaction, capping claim throughput for a single run regardless of how
  # many workers were running.
  #
  # Reading first keeps the steady state lock free, since a plain `SELECT` is a
  # consistent-snapshot read on every supported adapter. The writes stay
  # conditional, so losing the guard's race is benign: a stale read costs one
  # redundant no-op `UPDATE` on the single claim that actually transitions.
  class ClaimedState
    def self.mark_in_progress!(step)
      new(step).mark_in_progress!
    end

    def initialize(step)
      @step = step
    end

    def mark_in_progress!
      transition!(Ductwork::Step, step.id)

      run_status, pipeline_id = Ductwork::Run.where(id: step.run_id).pick(:status, :pipeline_id)

      return if run_status.nil?

      transition!(Ductwork::Run, step.run_id) unless run_status == "in_progress"

      return if Ductwork::Pipeline.where(id: pipeline_id, status: "in_progress").exists?

      transition!(Ductwork::Pipeline, pipeline_id)
    end

    private

    attr_reader :step

    def transition!(klass, id)
      klass
        .where(id:)
        .where.not(status: "in_progress")
        .update_all(status: "in_progress", updated_at: Time.current)
    end
  end
end
