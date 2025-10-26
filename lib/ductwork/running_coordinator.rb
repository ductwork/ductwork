# frozen_string_literal: true

module Ductwork
  class RunningCoordinator
    def initialize
      @mutex = Mutex.new
      @running = true
    end

    def running?
      mutex.synchronize { running }
    end

    def shutdown!
      mutex.synchronize { @running = false }
    end

    private

    attr_reader :mutex, :running
  end
end
