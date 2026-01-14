# frozen_string_literal: true

module Ductwork
  module Processes
    class JobWorker
      attr_reader :thread, :last_heartbeat_at, :job, :pipeline

      def initialize(pipeline, id)
        @pipeline = pipeline
        @id = id
        @running_context = Ductwork::RunningContext.new
        @thread = nil
        @last_heartbeat_at = Time.current
      end

      def start
        @thread = Thread.new { work_loop }
        @thread.name = name
      end

      alias restart start

      def alive?
        thread&.alive? || false
      end

      def stop
        running_context.shutdown!
      end

      def kill
        stop
        thread&.kill
      end

      def join(limit)
        thread&.join(limit)
      end

      def name
        "ductwork.job_worker.#{id}"
      end

      private

      attr_reader :id, :running_context

      def work_loop
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

          @job = Ductwork.wrap_with_app_executor do
            Job.claim_latest(pipeline)
          end

          if job.present?
            Ductwork.wrap_with_app_executor do
              job.execute(pipeline)
            end

            @job = nil
          else
            Ductwork.logger.debug(
              msg: "No job to claim, looping",
              role: :job_worker,
              pipeline: pipeline
            )
            sleep(polling_timeout)
          end

          @last_heartbeat_at = Time.current
        end

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

      def polling_timeout
        Ductwork.configuration.job_worker_polling_timeout(pipeline)
      end
    end
  end
end
