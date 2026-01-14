# frozen_string_literal: true

module Ductwork
  module Processes
    class PipelineAdvancerRunner
      def initialize(*klasses)
        @klasses = klasses
        @running_context = Ductwork::RunningContext.new
        @advancers = []

        Signal.trap(:INT) { running_context.shutdown! }
        Signal.trap(:TERM) { running_context.shutdown! }
        Signal.trap(:TTIN) do
          Thread.list.each do |thread|
            puts thread.name
            if thread.backtrace
              puts thread.backtrace.join("\n")
            else
              puts "No backtrace to dump"
            end
            puts
          end
        end
      end

      def run
        create_process!
        start_pipeline_advancers

        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :pipeline_advancer_runner,
          pipelines: klasses
        )

        while running_context.running?
          # TODO: Increase or make configurable
          sleep(5)
          check_thread_health
          report_heartbeat!
        end

        shutdown!
      end

      private

      attr_reader :klasses, :running_context, :advancers

      def start_pipeline_advancers
        klasses.each do |klass|
          advancer = Ductwork::Processes::PipelineAdvancer.new(klass)
          advancers.push(advancer)
          advancer.start

          Ductwork.logger.debug(
            msg: "Created new pipeline advancer",
            role: :pipeline_advancer_runner,
            pipeline: klass
          )
        end
      end

      def check_thread_health
        Ductwork.logger.debug(
          msg: "Checking threads health",
          role: :pipeline_advancer_runner,
          pipelines: klasses
        )
        advancers.each do |advancer|
          if !advancer.alive?
            advancer.restart

            Ductwork.logger.info(
              msg: "Restarted pipeline advancer",
              role: :pipeline_advancer_runner,
              pipeline: advancer.pipeline
            )
          end
        end
        Ductwork.logger.debug(
          msg: "Checked thread health",
          role: :pipeline_advancer_runner,
          pipelines: klasses
        )
      end

      def create_process!
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.create!(
            pid: ::Process.pid,
            machine_identifier: Ductwork::MachineIdentifier.fetch,
            last_heartbeat_at: Time.current
          )
        end
      end

      def report_heartbeat!
        Ductwork.logger.debug(msg: "Reporting heartbeat", role: :pipeline_advancer_runner)
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.report_heartbeat!
        end
        Ductwork.logger.debug(msg: "Reported heartbeat", role: :pipeline_advancer_runner)
      end

      def shutdown!
        log_shutting_down
        stop_running_context
        advancers.each(&:stop)
        await_threads_graceful_shutdown
        kill_remaining_threads
        delete_process!
      end

      def log_shutting_down
        Ductwork.logger.debug(msg: "Shutting down", role: :pipeline_advancer_runner)
      end

      def stop_running_context
        running_context.shutdown!
      end

      def await_threads_graceful_shutdown
        timeout = Ductwork.configuration.pipeline_shutdown_timeout
        deadline = Time.current + timeout

        Ductwork.logger.debug(
          msg: "Attempting graceful shutdown",
          role: :pipeline_advancer_runner
        )
        while Time.current < deadline && advancers.any?(&:alive?)
          advancers.each do |advancer|
            break if Time.current > deadline

            # TODO: Maybe make this configurable. If there's a ton of workers
            # it may not even get to the "later" ones depending on the timeout
            advancer.join(1)
          end
        end
      end

      def kill_remaining_threads
        advancers.each do |advancer|
          if advancer.alive?
            advancer.kill
            Ductwork.logger.debug(
              msg: "Killed thread",
              role: :pipeline_advancer_runner,
              thread: advancer.name
            )
          end
        end
      end

      def delete_process!
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.find_by!(
            pid: ::Process.pid,
            machine_identifier: Ductwork::MachineIdentifier.fetch
          ).delete
        end
      end
    end
  end
end
