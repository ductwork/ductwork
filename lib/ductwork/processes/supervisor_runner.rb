# frozen_string_literal: true

module Ductwork
  module Processes
    class SupervisorRunner
      def initialize(*pipelines)
        @pipelines = pipelines
        @supervisor = Ductwork::Processes::Supervisor.new
      end

      def run
        supervisor.add_worker(metadata: { pipelines: }) do
          Ductwork.logger.debug(
            msg: "Starting Pipeline Advancer process",
            role: :supervisor_runner
          )
          Ductwork::Processes::PipelineAdvancerRunner.new(*pipelines).run
        end

        pipelines.each do |pipeline|
          supervisor.add_worker(metadata: { pipeline: }) do
            Ductwork.logger.debug(
              msg: "Starting Job Worker Runner process",
              role: :supervisor_runner,
              pipeline: pipeline
            )
            Ductwork::Processes::JobWorkerRunner.new(*pipeline).run
          end
        end

        supervisor.run
      end

      private

      attr_reader :pipelines, :supervisor
    end
  end
end
