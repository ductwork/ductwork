# frozen_string_literal: true

module Ductwork
  module Processes
    class Launcher
      def self.start_processes!
        new.start_processes!
      end

      def initialize
        @pipelines = Ductwork.configuration.pipelines
        @runner_klass = if Ductwork.configuration.forking == "default"
                          case Ductwork.configuration.role
                          when "all"
                            process_supervisor_runner
                          when "advancer"
                            pipeline_advancer_runner
                          when "worker"
                            job_worker_runner
                          end
                        else
                          thread_supervisor_runner
                        end
      end

      def start_processes!
        runner_klass
          .new(*pipelines)
          .run
      end

      private

      attr_reader :pipelines, :runner_klass

      def thread_supervisor_runner
        Ductwork::Processes::ThreadSupervisorRunner
      end

      def process_supervisor_runner
        Ductwork::Processes::ProcessSupervisorRunner
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
