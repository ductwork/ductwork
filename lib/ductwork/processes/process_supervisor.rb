# frozen_string_literal: true

module Ductwork
  module Processes
    class ProcessSupervisor # rubocop:todo Metrics/ClassLength
      attr_reader :workers

      def initialize
        @running_context = Ductwork::RunningContext.new
        @workers = []

        run_hooks_for(:start)

        Signal.trap(:INT) { @running_context.shutdown! }
        Signal.trap(:TERM) { @running_context.shutdown! }
        Signal.trap(:TTIN) { puts "No threads to dump" }
      end

      def add_worker(metadata: {}, &block)
        pid = fork do
          block.call(metadata)
        end

        workers << { metadata:, pid:, block: }
        Ductwork.logger.debug(
          msg: "Started child process (#{pid}) with metadata #{metadata}",
          pid: pid
        )
      end

      def run
        adopt_or_create_process!

        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :process_supervisor,
          pid: ::Process.pid
        )

        while running_context.running?
          sleep(Ductwork.configuration.supervisor_polling_timeout)
          check_workers
          reap_process_records
        end

        shutdown
      end

      def shutdown
        running_context.shutdown!
        Ductwork.logger.debug(
          msg: "Beginning shutdown",
          role: :process_supervisor
        )

        terminate_gracefully
        wait_for_workers_to_exit
        terminate_immediately
        run_hooks_for(:stop)
      end

      private

      attr_reader :running_context

      def adopt_or_create_process!
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.adopt_or_create_current!(:supervisor)
        end
      end

      def check_workers
        Ductwork.logger.debug(
          msg: "Checking workers are alive",
          role: :process_supervisor
        )

        workers.each do |worker|
          if process_dead?(worker[:pid])
            old_pid = worker[:pid]
            sig_kill_process(old_pid)
            reap_process_record!(old_pid)
            new_pid = fork do
              worker[:block].call(worker[:metadata])
            end
            worker[:pid] = new_pid
            Ductwork.logger.debug(
              msg: "Restarted process (#{old_pid}) as (#{new_pid})",
              role: :process_supervisor,
              old_pid: old_pid,
              new_pid: new_pid
            )
          end
        end

        Ductwork.logger.debug(
          msg: "All workers are alive or revived",
          role: :process_supervisor
        )
      end

      def reap_process_records
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.reap_all!(:process_supervisor)
        end
      end

      def terminate_gracefully
        workers.each do |worker|
          Ductwork.logger.debug(
            msg: "Sending TERM signal to process (#{worker[:pid]})",
            role: :process_supervisor,
            pid: worker[:pid],
            signal: :TERM
          )
          ::Process.kill(:TERM, worker[:pid])
        end
      end

      def wait_for_workers_to_exit
        deadline = now + Ductwork.configuration.supervisor_shutdown_timeout

        while workers.any? && now < deadline
          sleep(0.1)
          workers.each_with_index do |worker, index|
            if ::Process.wait(worker[:pid], ::Process::WNOHANG)
              workers[index] = nil
              Ductwork.logger.debug(
                msg: "Child process (#{worker[:pid]}) stopped successfully",
                role: :process_supervisor,
                pid: worker[:pid]
              )
            end
          end
          @workers = workers.compact
        end
      end

      def terminate_immediately
        workers.each_with_index do |worker, index|
          Ductwork.logger.warn(
            msg: "Sending KILL signal to process (#{worker[:pid]})",
            role: :process_supervisor,
            pid: worker[:pid],
            signal: :KILL
          )
          sig_kill_process(worker[:pid])
          reap_process_record!(worker[:pid])
          workers[index] = nil
          Ductwork.logger.warn(
            msg: "Child process (#{worker[:pid]}) killed after timeout",
            role: :process_supervisor,
            pid: worker[:pid]
          )
        end

        @workers = workers.compact
      end

      def process_dead?(pid)
        machine_identifier = Ductwork::MachineIdentifier.fetch
        threshold = Ductwork::Process::REAP_THRESHOLD - 10.seconds
        sql = Ductwork::DatabaseClock.ago_sql("last_heartbeat_at", threshold)

        Ductwork.wrap_with_app_executor do
          Ductwork::Process
            .where(pid:, machine_identifier:)
            .where(sql)
            .exists?
        end
      end

      def sig_kill_process(pid)
        ::Process.kill(:KILL, pid)
        ::Process.wait(pid)
      rescue Errno::ECHILD, Errno::ESRCH
        # Process is already dead or reaped
      end

      def reap_process_record!(pid)
        machine_identifier = Ductwork::MachineIdentifier.fetch

        Ductwork.wrap_with_app_executor do
          Ductwork::Process
            .find_by(pid:, machine_identifier:)
            &.reap!(:process_supervisor)
        end
      end

      def run_hooks_for(event)
        Ductwork.hooks[:supervisor].fetch(event, []).each do |block|
          Ductwork.wrap_with_app_executor do
            block.call(self)
          end
        end
      end

      def now
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end
    end
  end
end
