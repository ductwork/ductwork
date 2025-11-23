# frozen_string_literal: true

module Ductwork
  module Processes
    class JobWorkerRunner
      def initialize(pipeline)
        @pipeline = pipeline
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
          role: :job_worker_runner,
          pipeline: pipeline
        )

        while running?
          # TODO: Increase or make configurable
          sleep(5)
          attempt_synchronize_threads
          report_heartbeat!
        end

        shutdown!
      end

      private

      attr_reader :pipeline, :running_context, :threads

      def worker_count
        Ductwork.configuration.job_worker_count(pipeline)
      end

      def create_threads
        worker_count.times.map do |i|
          job_worker = Ductwork::Processes::JobWorker.new(
            pipeline,
            running_context
          )
          Ductwork.logger.debug(
            msg: "Creating new thread",
            role: :job_worker_runner,
            pipeline: pipeline
          )
          thread = Thread.new do
            job_worker.run
          end
          thread.name = "ductwork.job_worker_#{i}"

          Ductwork.logger.debug(
            msg: "Created new thread",
            role: :job_worker_runner,
            pipeline: pipeline
          )

          thread
        end
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

      def running?
        running_context.running?
      end

      def attempt_synchronize_threads
        Ductwork.logger.debug(
          msg: "Attempting to synchronize threads",
          role: :job_worker_runner,
          pipeline: pipeline
        )
        threads.each { |thread| thread.join(0.1) }
        Ductwork.logger.debug(
          msg: "Synchronizing threads timed out",
          role: :job_worker_runner,
          pipeline: pipeline
        )
      end

      def report_heartbeat!
        Ductwork.logger.debug(msg: "Reporting heartbeat", role: :job_worker_runner)
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.report_heartbeat!
        end
        Ductwork.logger.debug(msg: "Reported heartbeat", role: :job_worker_runner)
      end

      def shutdown!
        running_context.shutdown!
        await_threads_graceful_shutdown
        kill_remaining_threads
        delete_process
      end

      def await_threads_graceful_shutdown
        timeout = Ductwork.configuration.job_worker_shutdown_timeout
        deadline = Time.current + timeout

        Ductwork.logger.debug(msg: "Attempting graceful shutdown", role: :job_worker_runner)
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
              role: :job_worker_runner,
              thread: thread.name
            )
          end
        end
      end

      def delete_process
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
