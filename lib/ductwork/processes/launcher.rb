# frozen_string_literal: true

module Ductwork
  module Processes
    class Launcher
      def self.start_processes!
        new.start_processes!
      end

      def initialize
        @pipelines = Ductwork.configuration.pipelines
        @runner_klass = case Ductwork.configuration.role
                        when "all"
                          supervisor_runner
                        when "advancer"
                          pipeline_advancer_runner
                        when "worker"
                          job_worker_runner
                        end
      end

      def start_processes!
        runner_klass
          .new(*pipelines)
          .run
      end

      private

      attr_reader :pipelines, :runner_klass

      def supervisor_runner
        Ductwork::Processes::SupervisorRunner
      end

      def pipeline_advancer_runner
        Ductwork::Processes::PipelineAdvancerRunner
      end

      def job_worker_runner
        Ductwork::Processes::JobWorkerRunner
      end
    end
  end
end
