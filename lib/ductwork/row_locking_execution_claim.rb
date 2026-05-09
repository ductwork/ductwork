# frozen_string_literal: true

module Ductwork
  class RowLockingExecutionClaim
    def initialize(klass, owner_process_id)
      @availability = nil
      @execution = nil
      @klass = klass
      @process_id = owner_process_id
    end

    def latest
      Ductwork::Record.transaction do
        claim_availability

        if availability.present?
          Ductwork.logger.debug(
            msg: "Job claimed",
            role: :job_worker,
            process_id: process_id,
            availability_id: availability.id
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
      end

      execution
    end

    private

    attr_reader :availability, :execution, :klass, :process_id

    def claim_availability
      sql = Ductwork::DatabaseClock.now_sql("ductwork_availabilities.started_at")
      @availability = Ductwork::Availability
                      .where(sql)
                      .where(completed_at: nil, pipeline_klass: klass)
                      .order(:started_at)
                      .lock("FOR UPDATE SKIP LOCKED")
                      .limit(1)
                      .first

      return unless availability

      completed_at = Time.current
      @execution = availability.execution

      availability.update_columns(completed_at:, process_id:)
      execution.update_columns(process_id:)
    end

    def update_state
      step = execution.job.step

      step.in_progress!
      step.run.in_progress!
      step.run.pipeline.in_progress!
    end
  end
end
