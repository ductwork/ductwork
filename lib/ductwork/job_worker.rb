# frozen_string_literal: true

module Ductwork
  class JobWorker
    def initialize(pipeline, running_context)
      @pipeline = pipeline
      @running_context = running_context
    end

    def run
      logger.debug(
        msg: "Entering main work loop",
        role: :job_worker,
        pipeline: pipeline
      )
      while running?
        logger.debug(
          msg: "Attempting to claim job",
          role: :job_worker,
          pipeline: pipeline
        )
        job = claim_job

        if job.present?
          logger.debug(
            msg: "Job claimed",
            role: :job_worker,
            pipeline: pipeline
          )

          process_job(job)
        else
          logger.debug(
            msg: "No job to claim, looping",
            role: :job_worker,
            pipeline: pipeline
          )
          sleep(1)
        end
      end

      shutdown
    end

    private

    attr_reader :pipeline, :running_context

    def running?
      running_context.running?
    end

    def claim_job
      process_id = ::Process.pid
      id = Ductwork::Availability
           .where(completed_at: nil)
           .order(:created_at)
           .limit(1)
           .pluck(:id)
           .first

      if id.present?
        # TODO: probably makes sense to use SQL here instead of relying
        # on ActiveRecord to construct the correct `UPDATE` query
        rows_updated = Ductwork::Availability
                       .where(id:, completed_at: nil)
                       .update_all(completed_at: Time.current, process_id:)

        if rows_updated == 1
          Ductwork::Job
            .joins(executions: :availability)
            .find_by(ductwork_availabilities: { id:, process_id: })
        end
      end
    end

    def process_job(job)
      logger.debug(
        msg: "Executing job",
        role: :job_worker,
        pipeline: pipeline,
        job_klass: job.klass
      )
      output_payload = Object.const_get(job.klass).new.execute(job.input_args)
      logger.debug(
        msg: "Executed job",
        role: :job_worker,
        pipeline: pipeline,
        job_klass: job.klass
      )
      job.update!(output_payload: output_payload)
      logger.debug(
        msg: "Saved output payload",
        role: :job_worker,
        pipeline: pipeline,
        job_klass: job.klass
      )
    end

    def shutdown
      logger.debug(
        msg: "Shutting down",
        role: :job_worker,
        pipeline: pipeline
      )
    end

    def logger
      Ductwork.configuration.logger
    end
  end
end
