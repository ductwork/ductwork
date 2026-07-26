# frozen_string_literal: true

module Ductwork
  module Processes
    class WorkerHealthCheck
      KILL_BUDGET = 3
      JOIN_TIMEOUT = 1

      def initialize(workers, role)
        @workers = workers
        @role = role
      end

      def check
        deadline = Time.current + KILL_BUDGET

        workers.each do |worker|
          if !worker.alive?
            restart_dead_worker(worker)
          elsif worker.stuck?
            restart_stuck_worker(worker, deadline)
          end
        end
      end

      private

      attr_reader :workers, :role

      def restart_dead_worker(worker)
        claimed_args = claimed_args_for(worker)

        worker.restart

        Ductwork.logger.warn(
          msg: "Restarted dead thread",
          role: role,
          thread: worker.name,
          **claimed_args
        )
      end

      def restart_stuck_worker(worker, deadline)
        if !dead_after_kill?(worker, deadline)
          Ductwork.logger.warn(
            msg: "Unable to confirm stuck thread died, deferring restart",
            role: role,
            thread: worker.name
          )

          return
        end

        worker.restart

        Ductwork.logger.warn(
          msg: "Killed and restarted stuck thread",
          role: role,
          thread: worker.name
        )
      end

      def dead_after_kill?(worker, deadline)
        worker.kill

        while worker.alive? && Time.current < deadline
          worker.join(JOIN_TIMEOUT)
          worker.kill if worker.alive?
        end

        !worker.alive?
      end

      def claimed_args_for(worker)
        if worker.is_a?(Ductwork::Processes::PipelineAdvancer)
          { branch_id: worker.branch&.id }
        else
          { job_id: worker.execution&.job_id }
        end
      end
    end
  end
end
