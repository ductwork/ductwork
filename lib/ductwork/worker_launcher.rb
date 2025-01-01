# frozen_string_literal: true

module Ductwork
  class WorkerLauncher
    def self.start!(configuration)
      supervisor = Ductwork::Supervisor.new

      configuration.pipelines.each do |pipeline|
        supervisor.add_worker(metadata: { pipeline: pipeline }) do
          Ductwork::PipelineWorker.new(pipeline).run
        end
      end

      supervisor.run
    end
  end
end
