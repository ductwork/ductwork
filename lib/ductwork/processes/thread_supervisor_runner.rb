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
            supervisor.add_worker(metadata: { pipelines: }) do
              Ductwork::Processes::PipelineAdvancer.new(pipeline).start
            end
          end
        end

        if Ductwork.configuration.role.in?(%w[all worker])
          pipelines.each do |pipeline|
            Ductwork.configuration.job_worker_count(pipeline).times do |i|
              supervisor.add_worker(metadata: { pipelines: }) do
                Ductwork::Processes::JobWorker.new(pipeline, i).start
              end
            end
          end
        end
      end

      private

      attr_reader :pipelines, :supervisor
    end
  end
end
