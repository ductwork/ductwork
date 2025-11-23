# frozen_string_literal: true

module Ductwork
  module Processes
    class PipelineAdvancerRunner
      def initialize(*klasses)
        @klasses = klasses
        @running_context = Ductwork::RunningContext.new
        @threads = create_threads

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
        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :pipeline_advancer_runner
        )

        while running_context.running?
          # TODO: Increase or make configurable
          sleep(5)
          attempt_synchronize_threads
          report_heartbeat!
        end

        shutdown
      end

      private

      attr_reader :klasses, :running_context, :threads

      def create_threads
        klasses.map do |klass|
          pipeline_advancer = Ductwork::Processes::PipelineAdvancer.new(
            running_context,
            klass
          )

          Ductwork.logger.debug(
            msg: "Creating new thread",
            role: :pipeline_advancer_runner,
            pipeline: klass
          )
          thread = Thread.new do
            Ductwork.wrap_with_app_executor do
              pipeline_advancer.run
            end
          end
          thread.name = "ductwork.pipeline_advancer.#{klass}"

          Ductwork.logger.debug(
            msg: "Created new thread",
            role: :pipeline_advancer_runner,
            thread: thread.name,
            pipeline: klass
          )

          thread
        end
      end

      def attempt_synchronize_threads
        Ductwork.logger.debug(
          msg: "Attempting to synchronize threads",
          role: :pipeline_advancer_runner
        )
        threads.each { |thread| thread.join(0.1) }
        Ductwork.logger.debug(
          msg: "Synchronizing threads timed out",
          role: :pipeline_advancer_runner
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

      def shutdown
        log_shutting_down
        stop_running_context
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
        while Time.current < deadline && threads.any?(&:alive?)
          threads.each do |thread|
            break if Time.current < deadline

            # TODO: Maybe make this configurable. If there's a ton of workers
            # it may not even get to the "later" ones depending on the timeout
            thread.join(1)
          end
        end
      end

      def kill_remaining_threads
        threads.each do |thread|
          if thread.alive?
            thread.kill
            Ductwork.logger.debug(
              msg: "Killed thread",
              role: :pipeline_advancer_runner,
              thread: thread.name
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
