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
    end

    def run
      while running
        sleep(1)
        check_workers
      end
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
          new_pid = fork do
            worker[:block].call(worker[:metadata])
          end
          worker[:pid] = new_pid
        end
      end
    end

    def terminate_gracefully
      workers.each do |worker|
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
          end
        end
        @workers = workers.compact
      end
    end

    def terminate_immediately
      workers.each_with_index do |worker, index|
        ::Process.kill(:KILL, worker[:pid])
        ::Process.wait(worker[:pid])
        workers[index] = nil
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
  end
end
