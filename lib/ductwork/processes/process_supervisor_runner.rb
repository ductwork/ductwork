# frozen_string_literal: true

module Ductwork
  module Processes
    class ProcessSupervisorRunner
      def initialize(*pipelines)
        @pipelines = pipelines
        @supervisor = Ductwork::Processes::ProcessSupervisor.new
      end

      def run
        supervisor.add_worker(metadata: { pipelines: }) do
          log_starting_pipline_advancer
          pipline_advancer_runner.new(*pipelines).run
        end

        pipelines.each do |pipeline|
          supervisor.add_worker(metadata: { pipeline: }) do
            log_starting_job_worker(pipeline)
            job_worker_runner.new(*pipeline).run
          end
        end

        supervisor.run
      end

      private

      attr_reader :pipelines, :supervisor

      def log_starting_pipline_advancer
        Ductwork.logger.debug(
          msg: "Starting Pipeline Advancer process",
          role: :process_supervisor_runner
        )
      end

      def pipline_advancer_runner
        Ductwork::Processes::PipelineAdvancerRunner
      end

      def log_starting_job_worker(pipeline)
        Ductwork.logger.debug(
          msg: "Starting Job Worker Runner process",
          role: :process_supervisor_runner,
          pipeline: pipeline
        )
      end

      def job_worker_runner
        Ductwork::Processes::JobWorkerRunner
      end
    end
  end
end
