# frozen_string_literal: true

module Ductwork
  module Processes
    class ThreadSupervisorRunner
      def initialize(*pipelines)
        @pipelines = pipelines
        @supervisor = Ductwork::Processes::ThreadSupervisor.new
      end

      def run
        if Ductwork.configuration.role.in?(%w[all advancer])
          pipelines.each do |pipeline|
            log_created_pipeline_advancer(pipeline)
            supervisor.add_worker(metadata: { pipeline: }) do
              pipeline_advancer.new(pipeline)
            end
          end
        end

        if Ductwork.configuration.role.in?(%w[all worker])
          pipelines.each do |pipeline|
            Ductwork.configuration.job_worker_count(pipeline).times do |index|
              log_created_job_worker(pipeline, index)
              supervisor.add_worker(metadata: { pipeline: }) do
                job_worker.new(pipeline, index)
              end
            end
          end
        end

        supervisor.run
      end

      private

      attr_reader :pipelines, :supervisor

      def log_created_pipeline_advancer(pipeline)
        Ductwork.logger.debug(
          msg: "Created new pipeline advancer",
          role: :thread_supervisor_runner,
          pipeline: pipeline
        )
      end

      def pipeline_advancer
        Ductwork::Processes::PipelineAdvancer
      end

      def log_created_job_worker(pipeline, index)
        Ductwork.logger.debug(
          msg: "Created new job worker",
          role: :thread_supervisor_runner,
          pipeline: pipeline,
          index: index
        )
      end

      def job_worker
        Ductwork::Processes::JobWorker
      end
    end
  end
end
