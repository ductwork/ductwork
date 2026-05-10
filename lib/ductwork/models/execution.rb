# frozen_string_literal: true

module Ductwork
  class Execution < Ductwork::Record
    belongs_to :job, class_name: "Ductwork::Job"
    belongs_to :process, class_name: "Ductwork::Process", optional: true
    has_one :availability, class_name: "Ductwork::Availability", foreign_key: "execution_id", dependent: :destroy
    has_one :attempt, class_name: "Ductwork::Attempt", foreign_key: "execution_id", dependent: :destroy
    has_one :result, class_name: "Ductwork::Result", foreign_key: "execution_id", dependent: :destroy

    validates :retry_count, presence: true
    validates :started_at, presence: true

    FAILED_EXECUTION_TIMEOUT = 10.seconds

    class CommitFailed < StandardError; end

    def call(pipeline, owner_process_id)
      Ductwork.logger.debug(
        msg: "Executing job",
        role: :job_worker,
        pipeline: pipeline,
        job_klass: job.klass
      )
      args = JSON.parse(job.input_args)["args"]
      instance = Object.const_get(job.klass).build_for_execution(job.step.run_id, *args)
      create_attempt!(started_at: Time.current)
      output_payload = nil

      begin
        output_payload = instance.execute
        Ductwork::FaultInjection.checkpoint(:during_job_execution)
      rescue StandardError => e
        errored!(e, owner_process_id)
        log_job_executed(pipeline, "error")

        return
      end

      succeeded!(output_payload, owner_process_id)
      log_job_executed(pipeline, "succeeded")
    end

    def succeeded!(output_payload, owner_process_id)
      completed_at = Time.current
      payload = JSON.dump({ payload: output_payload })

      Ductwork::Record.transaction do
        rows_updated = Ductwork::Execution
                       .where(id: id, completed_at: nil, process_id: owner_process_id)
                       .update_all(completed_at:)

        if rows_updated.zero?
          raise Ductwork::Execution::CommitFailed, "Reaper clobbered claimed job execution"
        end

        job.update!(output_payload: payload, completed_at: Time.current)
        attempt.update!(completed_at: Time.current)
        create_result!(result_type: "success")
        job.step.update!(status: :advancing)
      end
    end

    def crashed!
      Ductwork::Record.transaction do
        rows_updated = Ductwork::Execution
                       .where(id: id, completed_at: nil)
                       .update_all(completed_at: Time.current)

        return if rows_updated.zero?

        reload
        attempt&.update!(completed_at: Time.current)
        create_result!(result_type: "process_crashed")

        new_execution = job.executions.create!(
          retry_count: retry_count,
          crash_count: crash_count + 1,
          started_at: Time.current
        )
        new_execution.create_availability!(
          started_at: Time.current,
          pipeline_klass: job.step.run.pipeline_klass
        )
      end
    end

    def errored!(error, owner_process_id) # rubocop:todo Metrics
      run = job.step.run
      completed_at = Time.current
      max_retry = Ductwork.configuration.job_worker_max_retry(
        pipeline: run.pipeline_klass,
        step: job.klass
      )

      Ductwork::Record.transaction do # rubocop:todo Metrics/BlockLength
        rows_updated = Ductwork::Execution
                       .where(id: id, completed_at: nil, process_id: owner_process_id)
                       .update_all(completed_at:)

        if rows_updated.zero?
          raise Ductwork::Execution::CommitFailed, "Reaper clobbered claimed job execution"
        end

        attempt.update!(completed_at: Time.current)
        create_result!(
          result_type: "failure",
          error_klass: error.class.to_s,
          error_message: error.message,
          error_backtrace: error.backtrace.join("\n")
        )

        if retry_count < max_retry
          new_execution = job.executions.create!(
            retry_count: retry_count + 1,
            crash_count: crash_count,
            started_at: FAILED_EXECUTION_TIMEOUT.from_now
          )
          new_execution.create_availability!(
            started_at: FAILED_EXECUTION_TIMEOUT.from_now,
            pipeline_klass: run.pipeline_klass
          )

          Ductwork.logger.warn(
            msg: "Job errored",
            error_klass: error.class.name,
            error_message: error.message,
            job_id: job.id,
            job_klass: job.klass,
            run_id: run.id,
            role: :job_worker
          )
        elsif retry_count >= max_retry
          job.step.update!(status: :failed)

          Ductwork.logger.error(
            msg: "Job exhausted retries and failed",
            error_klass: error.class.name,
            error_message: error.message,
            job_id: job.id,
            job_klass: job.klass,
            run_id: run.id,
            role: :job_worker
          )
        end
      end
    end

    private

    def log_job_executed(pipeline, result_status)
      Ductwork.logger.info(
        msg: "Job executed",
        pipeline: pipeline,
        job_id: job.id,
        job_klass: job.klass,
        result: result_status,
        role: :job_worker
      )
    end
  end
end
