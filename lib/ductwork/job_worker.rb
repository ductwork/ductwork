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
      while running_context.running?
        logger.debug(
          msg: "Attempting to claim job",
          role: :job_worker,
          pipeline: pipeline
        )
        job = Job.claim_latest

        if job.present?
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
