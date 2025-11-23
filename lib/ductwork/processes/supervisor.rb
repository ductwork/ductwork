# frozen_string_literal: true

module Ductwork
  module Processes
    class Supervisor
      attr_reader :workers

      def initialize
        @running = true
        @workers = []

        run_hooks_for(:start)

        Signal.trap(:INT) { @running = false }
        Signal.trap(:TERM) { @running = false }
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
        Ductwork.logger.debug(msg: "Entering main work loop", role: :supervisor, pid: ::Process.pid)

        while running
          sleep(Ductwork.configuration.supervisor_polling_timeout)
          check_workers
        end

        shutdown
      end

      def shutdown
        @running = false

        Ductwork.logger.debug(msg: "Beginning shutdown", role: :supervisor)
        terminate_gracefully
        wait_for_workers_to_exit
        terminate_immediately
        run_hooks_for(:stop)
      end

      private

      attr_reader :running

      def check_workers
        Ductwork.logger.debug(msg: "Checking workers are alive", role: :supervisor)

        workers.each do |worker|
          if process_dead?(worker[:pid])
            old_pid = worker[:pid]
            new_pid = fork do
              worker[:block].call(worker[:metadata])
            end
            worker[:pid] = new_pid
            Ductwork.logger.debug(
              msg: "Restarted process (#{old_pid}) as (#{new_pid})",
              role: :supervisor,
              old_pid: old_pid,
              new_pid: new_pid
            )
          end
        end

        Ductwork.logger.debug(msg: "All workers are alive or revived", role: :supervisor)
      end

      def terminate_gracefully
        workers.each do |worker|
          Ductwork.logger.debug(
            msg: "Sending TERM signal to process (#{worker[:pid]})",
            role: :supervisor,
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
                role: :supervisor,
                pid: worker[:pid]
              )
            end
          end
          @workers = workers.compact
        end
      end

      def terminate_immediately
        workers.each_with_index do |worker, index|
          Ductwork.logger.debug(
            msg: "Sending KILL signal to process (#{worker[:pid]})",
            role: :supervisor,
            pid: worker[:pid],
            signal: :KILL
          )
          ::Process.kill(:KILL, worker[:pid])
          ::Process.wait(worker[:pid])
          workers[index] = nil
          Ductwork.logger.debug(
            msg: "Child process (#{worker[:pid]}) killed after timeout",
            role: :supervisor,
            pid: worker[:pid]
          )
        rescue Errno::ESRCH, Errno::ECHILD
          # no-op because process is already dead
        end

        @workers = workers.compact
      end

      def process_dead?(pid)
        machine_identifier = Ductwork::MachineIdentifier.fetch

        Ductwork.wrap_with_app_executor do
          Ductwork::Process
            .where(pid:, machine_identifier:)
            .where("last_heartbeat_at < ?", 5.minutes.ago)
            .exists?
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
