# frozen_string_literal: true

module Ductwork
  module Processes
    class PipelineAdvancer
      attr_reader :thread, :last_heartbeat_at, :pipeline

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

      alias restart start

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
          Branch.with_latest_claimed(klass) do |branch, transition, advancement|
            branch.advance!(transition, advancement)
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
