# frozen_string_literal: true

module Ductwork
  class ProcessLauncher
    def self.start!
      supervisor = Ductwork::Supervisor.new
      pipelines_to_advance = Ductwork.configuration.pipelines

      supervisor.add_worker(metadata: { pipelines: pipelines_to_advance }) do
        Ductwork::PipelineAdvancer.new(pipelines_to_advance).run
      end

      supervisor.run
    end
  end
end
