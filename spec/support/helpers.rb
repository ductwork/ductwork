# frozen_string_literal: true

module Helpers
  WORKER_SHUTDOWN_BUDGET = 5
  WORKER_JOIN_TIMEOUT = 0.1
  WAIT_FOR_TIMEOUT = 10
  WAIT_FOR_INTERVAL = 0.05

  def be_almost_now
    be_within(3.seconds).of(Time.current)
  end

  def wait_for(timeout: WAIT_FOR_TIMEOUT, interval: WAIT_FOR_INTERVAL)
    deadline = monotonic_now + timeout

    loop do
      result = yield
      return result if result

      if monotonic_now >= deadline
        raise "Timed out after #{timeout}s waiting for condition to be met"
      end

      sleep(interval)
    end
  end

  def kill_workers(*workers, budget: WORKER_SHUTDOWN_BUDGET)
    deadline = Time.current + budget
    workers = workers.flatten

    workers.each(&:stop)

    workers.each do |worker|
      while worker.alive? && Time.current < deadline
        worker.join(WORKER_JOIN_TIMEOUT)
      end

      next unless worker.alive?

      worker.kill
      worker.join(WORKER_JOIN_TIMEOUT)
    end
  end

  private

  def monotonic_now
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end
end
