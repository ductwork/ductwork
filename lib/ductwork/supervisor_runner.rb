# frozen_string_literal: true

module Ductwork
  # TODO: maybe rename to `Processes::Launcher`
  class SupervisorRunner
    def self.start!
      supervisor = Ductwork::Supervisor.new
      pipelines_to_advance = Ductwork.configuration.pipelines
      logger = Ductwork.configuration.logger

      supervisor.add_worker(metadata: { pipelines: pipelines_to_advance }) do
        logger.debug(
          msg: "Starting Pipeline Advancer process",
          role: :supervisor_runner
        )
        # TODO: maybe rename to `Processes::PipelineAdvancer`
        Ductwork::PipelineAdvancerRunner.new(*pipelines_to_advance).run
      end

      pipelines_to_advance.each do |pipeline|
        supervisor.add_worker(metadata: { pipeline: }) do
          logger.debug(
            msg: "Starting Job Worker Runner process",
            role: :supervisor_runner,
            pipeline: pipeline
          )
          # TODO: maybe rename to `Processes::JobWorkerRunner`
          Ductwork::JobWorkerRunner.new(pipeline).run
        end
      end

      supervisor.run
    end
  end
end
