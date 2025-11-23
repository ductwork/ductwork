# frozen_string_literal: true

module Ductwork
  class Job < Ductwork::Record # rubocop:todo Metrics/ClassLength
    belongs_to :step, class_name: "Ductwork::Step"
    has_many :executions, class_name: "Ductwork::Execution", foreign_key: "job_id", dependent: :destroy

    validates :klass, presence: true
    validates :started_at, presence: true
    validates :input_args, presence: true

    FAILED_EXECUTION_TIMEOUT = 10.seconds

    def self.claim_latest(klass) # rubocop:todo Metrics/MethodLength
      process_id = ::Process.pid
      id = Ductwork::Availability
           .joins(execution: { job: { step: :pipeline } })
           .where("ductwork_availabilities.started_at <= ?", Time.current)
           .where(completed_at: nil)
           .where(ductwork_pipelines: { klass: })
           .order(:created_at)
           .limit(1)
           .pluck(:id)
           .first

      if id.present?
        # TODO: probably makes sense to use SQL here instead of relying
        # on ActiveRecord to construct the correct `UPDATE` query
        rows_updated = nil
        Ductwork::Record.transaction do
          rows_updated = Ductwork::Availability
                         .where(id: id, completed_at: nil)
                         .update_all(completed_at: Time.current, process_id: process_id)
          Ductwork::Execution
            .joins(:availability)
            .where(completed_at: nil)
            .where(ductwork_availabilities: { id: })
            .update_all(process_id:)
        end

        if rows_updated == 1
          Ductwork.logger.debug(
            msg: "Job claimed",
            role: :job_worker,
            process_id: process_id,
            availability_id: id
          )
          Ductwork::Job
            .joins(executions: :availability)
            .find_by(ductwork_availabilities: { id:, process_id: })
        else
          Ductwork.logger.debug(
            msg: "Did not claim job, avoided race condition",
            role: :job_worker,
            process_id: process_id,
            availability_id: id
          )
          nil
        end
      end
    end

    def self.enqueue(step, args)
      job = Ductwork::Record.transaction do
        j = step.create_job!(
          klass: step.klass,
          started_at: Time.current,
          input_args: JSON.dump({ args: })
        )
        execution = j.executions.create!(
          started_at: Time.current,
          retry_count: 0
        )
        execution.create_availability!(
          started_at: Time.current
        )

        j
      end

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
      instance = Object.const_get(klass).new(args)
      run = execution.create_run!(
        started_at: Time.current
      )
      result = nil

      begin
        output_payload = instance.execute
        execution_succeeded!(execution, run, output_payload)
        result = "success"
      rescue StandardError => e
        execution_failed!(execution, run, e)
        result = "failure"
      ensure
        Ductwork.logger.info(
          msg: "Job executed",
          pipeline: pipeline,
          job_id: id,
          job_klass: klass,
          result: result,
          role: :job_worker
        )
      end
    end

    def return_value
      if output_payload.present?
        JSON.parse(output_payload).fetch("payload", nil)
      end
    end

    private

    def execution_succeeded!(execution, run, output_payload)
      payload = JSON.dump({ payload: output_payload })

      Ductwork::Record.transaction do
        update!(output_payload: payload, completed_at: Time.current)
        execution.update!(completed_at: Time.current)
        run.update!(completed_at: Time.current)
        execution.create_result!(result_type: "success")
        step.update!(status: :advancing)
      end
    end

    def execution_failed!(execution, run, error) # rubocop:disable Metrics/AbcSize
      halted = false
      pipeline = step.pipeline

      Ductwork::Record.transaction do
        execution.update!(completed_at: Time.current)
        run.update!(completed_at: Time.current)
        execution.create_result!(
          result_type: "failure",
          error_klass: error.class.to_s,
          error_message: error.message,
          error_backtrace: error.backtrace
        )

        if execution.retry_count < Ductwork.configuration.job_worker_max_retry
          new_execution = executions.create!(
            retry_count: execution.retry_count + 1,
            started_at: FAILED_EXECUTION_TIMEOUT.from_now
          )
          new_execution.create_availability!(
            started_at: FAILED_EXECUTION_TIMEOUT.from_now
          )
        elsif execution.retry_count >= Ductwork.configuration.job_worker_max_retry
          halted = true

          step.update!(status: :failed)
          pipeline.halted!
        end
      end

      Ductwork.logger.warn(
        msg: "Job errored",
        error_klass: error.class.name,
        error_message: error.message,
        job_id: id,
        job_klass: klass,
        pipeline_id: pipeline.id,
        role: :job_worker
      )

      # NOTE: perform lifecycle hook execution outside of the transaction as
      # to not unnecessarily hold it open
      if halted
        klass = JSON.parse(pipeline.definition).dig("metadata", "on_halt", "klass")

        if klass.present?
          Object.const_get(klass).new(error).execute
        end
      end
    end
  end
end
