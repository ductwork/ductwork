# frozen_string_literal: true

module Ductwork
  class RowLockingExecutionClaim
    def initialize(klass)
      @availability = nil
      @execution = nil
      @klass = klass
      @process_id = Ductwork::Process.current.id
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
      @availability = Ductwork::Availability
                      .where("ductwork_availabilities.started_at <= ?", Time.current)
                      .where(completed_at: nil, pipeline_klass: klass)
                      .order(:started_at)
                      .lock("FOR UPDATE SKIP LOCKED")
                      .limit(1)
                      .first

      return unless availability

      availability.update_columns(
        completed_at: Time.current,
        process_id: process_id
      )
    end

    def update_state
      @execution = availability.execution
      step = execution.job.step

      step.in_progress!
      step.run.in_progress!
      step.run.pipeline.in_progress!
    end
  end
end
