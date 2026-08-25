# frozen_string_literal: true

module StartedWorkerRegistry
  class << self
    def started
      @started ||= []
    end

    def register(worker)
      started << worker
    end

    def reset!
      @started = []
    end
  end

  def start
    started = super
    StartedWorkerRegistry.register(self) if started

    started
  end
end

Ductwork::Processes::JobWorker.prepend(StartedWorkerRegistry)
Ductwork::Processes::PipelineAdvancer.prepend(StartedWorkerRegistry)

RSpec.configure do |config|
  config.prepend_after do |example|
    kill_workers(StartedWorkerRegistry.started)
    StartedWorkerRegistry.reset!

    leaked = Thread.list.select do |thread|
      thread.name.to_s.start_with?("ductwork.")
    end

    unless leaked.empty?
      warn(
        "Leaked ductwork worker threads after #{example.location}: " \
        "#{leaked.map(&:name).join(", ")}"
      )

      leaked.each do |thread|
        thread.join(Helpers::WORKER_JOIN_TIMEOUT)
        next unless thread.alive?

        thread.kill
        thread.join(Helpers::WORKER_JOIN_TIMEOUT)
      end
    end
  end
end
