# frozen_string_literal: true

module Ductwork
  module Processes
    class JobWorker
      attr_reader :thread, :last_heartbeat_at, :execution, :pipeline

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
        "ductwork.job_worker.#{pipeline}.#{id}"
      end

      private

      attr_reader :id, :running_context

      def work_loop # rubocop:todo Metrics
        run_hooks_for(:start)

        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :job_worker,
          pipeline: pipeline
        )

        while running_context.running?
          owner_process_id = nil

          begin
            Ductwork.logger.debug(
              msg: "Attempting to claim job",
              role: :job_worker,
              pipeline: pipeline
            )

            @execution = Ductwork.wrap_with_app_executor do
              owner_process_id = Ductwork::Process.current.id
              Ductwork::ExecutionClaim.new(pipeline).latest
            end

            if execution.present?
              Ductwork::FaultInjection.checkpoint(:after_job_claim)

              Ductwork.wrap_with_app_executor do
                execution.call(pipeline, owner_process_id)
              end

              @execution = nil
            else
              Ductwork.logger.debug(
                msg: "No job to claim, looping",
                role: :job_worker,
                pipeline: pipeline
              )
              sleep(polling_timeout)
            end
          rescue StandardError => e
            if execution.present?
              Ductwork.wrap_with_app_executor do
                execution.crashed!
              end
            end

            Ductwork.logger.error(
              msg: "Unexpected error in work loop",
              error_klass: e.class.name,
              error_message: e.message,
              job_id: execution&.job_id,
              job_klass: execution&.job&.klass,
              role: :job_worker,
              pipeline: pipeline
            )

            @execution = nil
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
