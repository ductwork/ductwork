# frozen_string_literal: true

module Ductwork
  class ProcessLauncher
    def self.start!
      supervisor = Ductwork::Supervisor.new

      Ductwork.configuration.pipelines.each do |pipeline|
        supervisor.add_worker(metadata: { pipeline: pipeline }) do
          Ductwork::PipelineWorker.new(pipeline).run
        end
      end

      supervisor.run
    end
  end
end
