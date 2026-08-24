# frozen_string_literal: true

module Helpers
  WORKER_KILL_BUDGET = 5
  WORKER_JOIN_TIMEOUT = 0.1

  def be_almost_now
    be_within(3.seconds).of(Time.current)
  end

  def kill_workers(*workers, budget: WORKER_KILL_BUDGET)
    deadline = Time.current + budget

    workers.flatten.each do |worker|
      worker.kill

      while worker.alive? && Time.current < deadline
        worker.join(WORKER_JOIN_TIMEOUT)
        worker.kill if worker.alive?
      end
    end
  end
end
