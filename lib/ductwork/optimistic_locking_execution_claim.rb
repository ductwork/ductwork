# frozen_string_literal: true

module Ductwork
  class OptimisticLockingExecutionClaim
    def initialize(klass, owner_process_id)
      @id = nil
      @execution = nil
      @klass = klass
      @process_id = owner_process_id
    end

    def latest
      Ductwork::Record.transaction do # rubocop:todo Metrics/BlockLength
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

            @execution = find_execution
            execution.update_columns(process_id:)

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
      end

      execution
    end

    private

    attr_reader :id, :execution, :klass, :process_id

    def latest_availability_id
      sql = Ductwork::DatabaseClock.now_sql("ductwork_availabilities.started_at")

      Ductwork::Availability
        .where(sql)
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

    def find_execution
      Ductwork::Execution
        .joins(:availability)
        .find_by!(ductwork_availabilities: { id:, process_id: })
    end

    def update_state
      step = execution.job.step

      Ductwork::Step
        .where(id: step.id)
        .where.not(status: "in_progress")
        .update_all(status: "in_progress", updated_at: Time.current)
      Ductwork::Run
        .where(id: step.run_id)
        .where.not(status: "in_progress")
        .update_all(status: "in_progress", updated_at: Time.current)
      Ductwork::Pipeline
        .where(id: Ductwork::Run.where(id: step.run_id).select(:pipeline_id))
        .where.not(status: "in_progress")
        .update_all(status: "in_progress", updated_at: Time.current)
    end
  end
end
