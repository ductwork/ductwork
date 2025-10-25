# frozen_string_literal: true

module Ductwork
  class JobWorkerLauncher
    def initialize(pipeline)
      @pipeline = pipeline
    end

    def run
      # Ductwork.configuration.job_thread_count.times.map do
      #   Thread.new do
      #     Ductwork::JobWorker.new(pipeline).run
      #   end
      # end.each(&:join)
    end

    private

    attr_reader :pipeline
  end
end
