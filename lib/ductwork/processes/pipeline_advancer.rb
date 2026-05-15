# frozen_string_literal: true

module Ductwork
  module Processes
    class PipelineAdvancer
      attr_reader :thread, :last_heartbeat_at, :branch

      def initialize(klass, index = nil)
        @klass = klass
        @index = index || 0
        @running_context = Ductwork::RunningContext.new
        @last_heartbeat_at = Time.current
        @thread = nil
      end

      def start
        @thread = Thread.new { work_loop }
        @thread.name = name
      end

      def restart
        cleanup_dead_thread!
        start
      end

      def alive?
        thread&.alive? || false
      end

      def stop
        running_context.shutdown!
      end

      def kill
        stop
        thread&.kill
      end

      def join(limit)
        thread&.join(limit)
      end

      def name
        "ductwork.pipeline_advancer.#{klass}.#{index}"
      end

      private

      attr_reader :klass, :index, :running_context

      def work_loop
        run_hooks_for(:start)

        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :pipeline_advancer,
          pipeline: klass
        )

        while running_context.running?
          Ductwork.wrap_with_app_executor do
            Branch.with_latest_claimed(klass) do |branch, transition, advancement|
              @branch = branch

              branch.advance!(transition, advancement)

              Ductwork::FaultInjection.checkpoint(:after_branch_advancement)
            ensure
              @branch = nil
            end
          end

          @last_heartbeat_at = Time.current

          sleep(polling_timeout)
        end

        Ductwork.logger.debug(
          msg: "Shutting down",
          role: :pipeline_advancer,
          pipeline: klass
        )

        run_hooks_for(:stop)
      end

      def cleanup_dead_thread!
        if branch.present?
          advancement = branch
                        .transitions
                        .joins(:advancements)
                        .where(ductwork_advancements: { completed_at: nil })
                        .first
                        &.advancements
                        &.find_by(completed_at: nil)

          advancement&.thread_crashed!
          branch.reload.release!(branch.claim_token)
        end
      ensure
        @branch = nil
      end

      def run_hooks_for(event)
        Ductwork.hooks[:advancer].fetch(event, []).each do |block|
          Ductwork.wrap_with_app_executor do
            block.call(self)
          end
        end
      end

      def polling_timeout
        Ductwork.configuration.pipeline_polling_timeout(klass)
      end
    end
  end
end
