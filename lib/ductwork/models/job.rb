# frozen_string_literal: true

module Ductwork
  class Job < Ductwork::Record
    belongs_to :step, class_name: "Ductwork::Step"
    has_many :executions, class_name: "Ductwork::Execution", foreign_key: "job_id", dependent: :destroy

    validates :klass, presence: true
    validates :started_at, presence: true
    validates :input_args, presence: true

    FAILED_EXECUTION_TIMEOUT = 10.seconds

    def self.claim_latest(klass)
      Ductwork::JobClaim.new(klass).latest
    end

    def self.enqueue(step, *args)
      job = step.create_job!(
        klass: step.klass,
        started_at: Time.current,
        input_args: JSON.dump({ args: })
      )
      execution = job.executions.create!(
        started_at: Time.current,
        retry_count: 0
      )
      execution.create_availability!(
        started_at: Time.current,
        pipeline_klass: step.run.pipeline_klass
      )

      Ductwork.logger.info(
        msg: "Job enqueued",
        job_id: job.id,
        job_klass: job.klass
      )

      job
    end

    def execute(pipeline)
      # i don't _really_ like this, but it should be fine for now...
      execution = executions.order(:created_at).last
      Ductwork.logger.debug(
        msg: "Executing job",
        role: :job_worker,
        pipeline: pipeline,
        job_klass: klass
      )
      args = JSON.parse(input_args)["args"]
      instance = Object.const_get(klass).build_for_execution(step.run_id, *args)
      attempt = execution.create_attempt!(
        started_at: Time.current
      )
      result = nil

      begin
        output_payload = instance.execute
        execution_succeeded!(execution, attempt, output_payload)
        result = "success"
      rescue StandardError => e
        execution_errored!(execution, attempt, e)
        result = "failure"
      ensure
        Ductwork.logger.info(
          msg: "Job executed",
          pipeline: pipeline,
          job_id: id,
          job_klass: klass,
          result: result || "killed",
          role: :job_worker
        )
      end
    end

    def return_value
      if output_payload.present?
        JSON.parse(output_payload).fetch("payload", nil)
      end
    end

    def execution_crashed!(execution)
      Ductwork::Record.transaction do
        execution.update!(completed_at: Time.current)
        execution.attempt&.update!(completed_at: Time.current)
        execution.create_result!(result_type: "process_crashed")

        new_execution = executions.create!(
          retry_count: execution.retry_count,
          started_at: FAILED_EXECUTION_TIMEOUT.from_now
        )
        new_execution.create_availability!(
          started_at: FAILED_EXECUTION_TIMEOUT.from_now,
          pipeline_klass: step.run.pipeline_klass
        )
      end
    end

    private

    def execution_succeeded!(execution, attempt, output_payload)
      payload = JSON.dump({ payload: output_payload })

      Ductwork::Record.transaction do
        update!(output_payload: payload, completed_at: Time.current)
        execution.update!(completed_at: Time.current)
        attempt.update!(completed_at: Time.current)
        execution.create_result!(result_type: "success")
        step.update!(status: :advancing)
      end
    end

    def execution_errored!(execution, attempt, error) # rubocop:todo Metrics
      run = step.run
      max_retry = Ductwork.configuration.job_worker_max_retry(
        pipeline: run.pipeline_klass,
        step: klass
      )

      Ductwork::Record.transaction do # rubocop:todo Metrics/BlockLength
        execution.update!(completed_at: Time.current)
        attempt.update!(completed_at: Time.current)
        execution.create_result!(
          result_type: "failure",
          error_klass: error.class.to_s,
          error_message: error.message,
          error_backtrace: error.backtrace.join("\n")
        )

        if execution.retry_count < max_retry
          new_execution = executions.create!(
            retry_count: execution.retry_count + 1,
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
            job_id: id,
            job_klass: klass,
            run_id: run.id,
            role: :job_worker
          )
        elsif execution.retry_count >= max_retry
          step.update!(status: :failed)

          Ductwork.logger.error(
            msg: "Job exhausted retries and failed",
            error_klass: error.class.name,
            error_message: error.message,
            job_id: id,
            job_klass: klass,
            run_id: run.id,
            role: :job_worker
          )
        end
      end
    end
  end
end
