# frozen_string_literal: true

module Ductwork
  module Processes
    class SupervisorRunner
      def self.start!
        supervisor = Ductwork::Processes::Supervisor.new
        pipelines_to_advance = Ductwork.configuration.pipelines

        supervisor.add_worker(metadata: { pipelines: pipelines_to_advance }) do
          Ductwork.logger.debug(
            msg: "Starting Pipeline Advancer process",
            role: :supervisor_runner
          )
          Ductwork::Processes::PipelineAdvancerRunner
            .new(*pipelines_to_advance).run
        end

        pipelines_to_advance.each do |pipeline|
          supervisor.add_worker(metadata: { pipeline: }) do
            Ductwork.logger.debug(
              msg: "Starting Job Worker Runner process",
              role: :supervisor_runner,
              pipeline: pipeline
            )
            Ductwork::Processes::JobWorkerRunner.new(pipeline).run
          end
        end

        supervisor.run
      end
    end
  end
end
