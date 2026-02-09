# frozen_string_literal: true

module Ductwork
  class OptimisticLockingJobClaim
    def initialize(klass)
      @id = nil
      @job = nil
      @klass = klass
      @process_id = ::Process.pid
    end

    def latest
      @id = latest_availability_id

      if id.present?
        rows_updated = claim_availability

        if rows_updated == 1
          Ductwork.logger.debug(
            msg: "Job claimed",
            role: :job_worker,
            process_id: process_id,
            availability_id: id
          )

          @job = find_job

          update_state
        else
          Ductwork.logger.debug(
            msg: "Did not claim job, avoided race condition",
            role: :job_worker,
            process_id: process_id,
            availability_id: id
          )
        end
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

    def latest_availability_id
      Ductwork::Availability
        .where("ductwork_availabilities.started_at <= ?", Time.current)
        .where(completed_at: nil, pipeline_klass: klass)
        .order(:started_at)
        .limit(1)
        .pluck(:id)
        .first
    end

    def claim_availability
      Ductwork::Availability
        .where(id: id, completed_at: nil)
        .update_all(completed_at: Time.current, process_id: process_id)
    end

    def find_job
      Ductwork::Job
        .joins(executions: :availability)
        .find_by!(ductwork_availabilities: { id:, process_id: })
    end

    def update_state
      Ductwork::Record.transaction do
        Ductwork::Execution
          .joins(:availability)
          .where(completed_at: nil)
          .where(ductwork_availabilities: { id: })
          .sole
          .update!(process_id:)
        job.step.in_progress!
        job.step.pipeline.in_progress!
      end
    end
  end
end
