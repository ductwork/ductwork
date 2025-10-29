# frozen_string_literal: true

module Ductwork
  class Supervisor
    DEFAULT_TIMEOUT = 10 # seconds

    attr_reader :workers

    def initialize(timeout: DEFAULT_TIMEOUT)
      @running = true
      @workers = []
      @timeout = timeout

      Signal.trap(:INT) { @running = false }
      Signal.trap(:TERM) { @running = false }
    end

    def add_worker(metadata: {}, &block)
      pid = fork do
        block.call(metadata)
      end

      workers << { metadata: metadata, pid: pid, block: block }
      logger.debug(
        msg: "Started process (#{pid}) with metadata #{metadata}",
        role: :supervisor,
        pid: pid
      )
    end

    def run
      logger.debug(msg: "Entering main work loop", role: :supervisor)
      while running
        sleep(1)
        logger.debug(msg: "Checking workers are alive", role: :supervisor)
        check_workers
      end

      logger.debug(msg: "Beginning shutdown", role: :supervisor)
      shutdown
    end

    def shutdown
      @running = false

      terminate_gracefully
      wait_for_workers_to_exit
      terminate_immediately
    end

    private

    attr_reader :running, :timeout

    def check_workers
      workers.each do |worker|
        if process_dead?(worker[:pid])
          old_pid = worker[:pid]
          new_pid = fork do
            worker[:block].call(worker[:metadata])
          end
          worker[:pid] = new_pid
          logger.debug(
            msg: "Restarted process (#{old_pid}) as (#{new_pid})",
            role: :supervisor,
            old_pid: old_pid,
            new_pid: new_pid
          )
        end
      end
    end

    def terminate_gracefully
      workers.each do |worker|
        logger.debug(
          msg: "Sending TERM signal to process (#{worker[:pid]})",
          role: :supervisor,
          pid: worker[:pid],
          signal: :TERM
        )
        ::Process.kill(:TERM, worker[:pid])
      end
    end

    def wait_for_workers_to_exit
      deadline = now + timeout

      while workers.any? && now < deadline
        sleep(0.1)
        workers.each_with_index do |worker, index|
          if ::Process.wait(worker[:pid], ::Process::WNOHANG)
            workers[index] = nil
            logger.debug(
              msg: "Process (#{worker[:pid]}) stopped successfully",
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
        logger.debug(
          msg: "Sending KILL signal to process (#{worker[:pid]})",
          role: :supervisor,
          pid: worker[:pid],
          signal: :KILL
        )
        ::Process.kill(:KILL, worker[:pid])
        ::Process.wait(worker[:pid])
        workers[index] = nil
        logger.debug(
          msg: "Process (#{worker[:pid]}) killed after timeout",
          role: :supervisor,
          pid: worker[:pid]
        )
      rescue Errno::ESRCH, Errno::ECHILD
        # no-op because process is already dead
      end

      @workers = workers.compact
    end

    def process_dead?(pid)
      ::Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM
      false
    end

    def now
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end

    def logger
      Ductwork.configuration.logger
    end
  end
end
