# frozen_string_literal: true

module Ductwork
  module Processes
    class JobWorkerRunner
      def initialize(*pipelines)
        @pipelines = pipelines
        @running_context = Ductwork::RunningContext.new
        @job_workers = []

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
        create_process_record!
        start_job_workers

        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :job_worker_runner,
          pipelines: pipelines
        )

        while running?
          # TODO: Increase or make configurable
          sleep(5)
          check_thread_health
          report_heartbeat!
        end

        shutdown!
      end

      private

      attr_reader :pipelines, :running_context, :job_workers

      def create_process_record!
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.create!(
            pid: ::Process.pid,
            machine_identifier: Ductwork::MachineIdentifier.fetch,
            last_heartbeat_at: Time.current
          )
        end
      end

      def start_job_workers
        pipelines.each do |pipeline|
          Ductwork.configuration.job_worker_count(pipeline).times do |i|
            job_worker = Ductwork::Processes::JobWorker.new(pipeline, i)
            job_workers.push(job_worker)
            job_worker.start

            Ductwork.logger.debug(
              msg: "Created new job worker",
              role: :job_worker_runner,
              pipeline: pipeline
            )
          end
        end
      end

      def running?
        running_context.running?
      end

      def check_thread_health
        Ductwork.logger.debug(
          msg: "Checking thread health",
          role: :job_worker_runner,
          pipelines: pipelines
        )
        job_workers.each do |job_worker|
          if !job_worker.alive?
            job_worker.restart

            Ductwork.logger.info(
              msg: "Restarted job worker",
              role: :job_worker_runner,
              pipeline: job_worker.pipeline
            )
          end
        end
        Ductwork.logger.debug(
          msg: "Checked thread health",
          role: :job_worker_runner,
          pipelines: pipelines
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
        job_workers.each(&:stop)
        await_threads_graceful_shutdown
        kill_remaining_job_workers
        delete_process_record!
      end

      def await_threads_graceful_shutdown
        timeout = Ductwork.configuration.job_worker_shutdown_timeout
        deadline = Time.current + timeout

        Ductwork.logger.debug(
          msg: "Attempting graceful shutdown",
          role: :job_worker_runner
        )

        while Time.current < deadline && job_workers.any?(&:alive?)
          job_workers.each do |job_worker|
            break if Time.current > deadline

            # TODO: Maybe make this configurable. If there's a ton of workers
            # it may not even get to the "later" ones depending on the timeout
            job_worker.join(1)
          end
        end
      end

      def kill_remaining_job_workers
        job_workers.each do |job_worker|
          if job_worker.alive?
            job_worker.kill
            Ductwork.logger.debug(
              msg: "Killed thread",
              role: :job_worker_runner,
              thread: job_worker.name
            )
          end
        end
      end

      def delete_process_record!
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
