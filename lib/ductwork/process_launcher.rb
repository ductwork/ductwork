# frozen_string_literal: true

module Ductwork
  # TODO: maybe rename to `Processes::Launcher`
  class ProcessLauncher
    def self.start!
      supervisor = Ductwork::Supervisor.new
      pipelines_to_advance = Ductwork.configuration.pipelines

      supervisor.add_worker(metadata: { pipelines: pipelines_to_advance }) do
        # TODO: maybe rename to `Processes::PipelineAdvancer`
        Ductwork::PipelineAdvancer.new(*pipelines_to_advance).run
      end

      pipelines_to_advance.each do |pipeline|
        supervisor.add_worker(metadata: { pipeline: }) do
          # TODO: maybe rename to `Processes::JobWorkerRunner`
          Ductwork::JobWorkerRunner.new(pipeline).run
        end
      end

      supervisor.run
    end
  end
end
