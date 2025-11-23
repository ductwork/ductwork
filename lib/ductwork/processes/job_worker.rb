# frozen_string_literal: true

module Ductwork
  module Processes
    class JobWorker
      def initialize(pipeline, running_context)
        @pipeline = pipeline
        @running_context = running_context
      end

      def run
        run_hooks_for(:start)
        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :job_worker,
          pipeline: pipeline
        )
        while running_context.running?
          Ductwork.logger.debug(
            msg: "Attempting to claim job",
            role: :job_worker,
            pipeline: pipeline
          )
          job = Ductwork.wrap_with_app_executor do
            Job.claim_latest(pipeline)
          end

          if job.present?
            Ductwork.wrap_with_app_executor do
              job.execute(pipeline)
            end
          else
            Ductwork.logger.debug(
              msg: "No job to claim, looping",
              role: :job_worker,
              pipeline: pipeline
            )
            sleep(Ductwork.configuration.job_worker_polling_timeout)
          end
        end

        shutdown
      end

      private

      attr_reader :pipeline, :running_context

      def shutdown
        Ductwork.logger.debug(
          msg: "Shutting down",
          role: :job_worker,
          pipeline: pipeline
        )
        run_hooks_for(:stop)
      end

      def run_hooks_for(event)
        Ductwork.hooks[:worker].fetch(event, []).each do |block|
          Ductwork.wrap_with_app_executor do
            block.call(self)
          end
        end
      end
    end
  end
end
