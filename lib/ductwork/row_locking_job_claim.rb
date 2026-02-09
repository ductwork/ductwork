# frozen_string_literal: true

module Ductwork
  class RowLockingJobClaim
    def initialize(klass)
      @id = nil
      @job = nil
      @klass = klass
      @process_id = ::Process.pid
    end

    def latest
      rows_updated = attempt_availability_claim

      if rows_updated == 1
        Ductwork.logger.debug(
          msg: "Job claimed",
          role: :job_worker,
          process_id: process_id,
          availability_id: id
        )
        update_state
      else
        Ductwork.logger.debug(
          msg: "No available job to claim",
          role: :job_worker,
          process_id: process_id,
          pipeline: klass
        )
      end

      job
    end

    private

    attr_reader :id, :job, :klass, :process_id

    def attempt_availability_claim
      Ductwork::Record.transaction do
        @id = Ductwork::Availability
              .where("ductwork_availabilities.started_at <= ?", Time.current)
              .where(completed_at: nil, pipeline_klass: klass)
              .order(:started_at)
              .lock("FOR UPDATE SKIP LOCKED")
              .limit(1)
              .ids
              .first

        if id.present?
          Ductwork::Availability
            .where(id: id, completed_at: nil)
            .update_all(completed_at: Time.current, process_id: process_id)
        else
          0
        end
      end
    end

    def update_state
      Ductwork::Record.transaction do
        execution = Ductwork::Execution
                    .joins(:availability)
                    .where(completed_at: nil)
                    .where(ductwork_availabilities: { id: })
                    .sole
        @job = execution.job

        execution.update!(process_id:)
        job.step.in_progress!
        job.step.pipeline.in_progress!
      end
    end
  end
end
