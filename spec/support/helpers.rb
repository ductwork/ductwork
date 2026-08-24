# frozen_string_literal: true

module Helpers
  WORKER_SHUTDOWN_BUDGET = 5
  WORKER_JOIN_TIMEOUT = 0.1

  def be_almost_now
    be_within(3.seconds).of(Time.current)
  end

  def kill_workers(*workers, budget: WORKER_SHUTDOWN_BUDGET)
    deadline = Time.current + budget
    workers = workers.flatten

    workers.each(&:stop)

    workers.each do |worker|
      worker.join(WORKER_JOIN_TIMEOUT) while worker.alive? && Time.current < deadline

      next unless worker.alive?

      worker.kill
      worker.join(WORKER_JOIN_TIMEOUT)
    end
  end
end
