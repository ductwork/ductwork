# frozen_string_literal: true

RSpec.configure do |config|
  config.after do |example|
    leaked = Thread.list.select do |thread|
      thread.name.to_s.start_with?("ductwork.")
    end

    next if leaked.empty?

    warn(
      "Leaked ductwork worker threads after #{example.location}: " \
      "#{leaked.map(&:name).join(", ")}"
    )

    deadline = Time.current + Helpers::WORKER_KILL_BUDGET

    leaked.each do |thread|
      thread.kill

      while thread.alive? && Time.current < deadline
        thread.join(Helpers::WORKER_JOIN_TIMEOUT)
        thread.kill if thread.alive?
      end
    end
  end
end
