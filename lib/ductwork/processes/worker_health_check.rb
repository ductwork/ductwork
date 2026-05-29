# frozen_string_literal: true

module Ductwork
  module Processes
    class WorkerHealthCheck
      def initialize(workers, role)
        @workers = workers
        @role = role
      end

      def check
        workers.each do |worker|
          if !worker.alive?
            restart_dead_worker(worker)
          elsif worker.stuck?
            restart_stuck_worker(worker)
          end
        end
      end

      private

      attr_reader :workers, :role

      def restart_dead_worker(worker)
        worker.restart

        claimed_args = if worker.is_a?(Ductwork::Processes::PipelineAdvancer)
                         { branch_id: worker.branch&.id }
                       else
                         { job_id: worker.execution&.job_id }
                       end

        Ductwork.logger.warn(
          msg: "Restarted dead thread",
          role: role,
          thread: worker.name,
          **claimed_args
        )
      end

      def restart_stuck_worker(worker)
        worker.kill if worker.alive?
        worker.join(1)
        worker.restart

        Ductwork.logger.warn(
          msg: "Killed and restarted stuck thread",
          role: role,
          thread: worker.name
        )
      end
    end
  end
end
