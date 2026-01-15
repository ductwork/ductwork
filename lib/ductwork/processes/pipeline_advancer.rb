# frozen_string_literal: true

module Ductwork
  module Processes
    class PipelineAdvancer
      attr_reader :thread, :last_heartbeat_at, :pipeline

      def initialize(klass)
        @klass = klass
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
        "ductwork.pipeline_advancer.#{klass}"
      end

      private

      attr_reader :running_context, :klass

      def work_loop # rubocop:todo Metrics
        run_hooks_for(:start)

        Ductwork.logger.debug(
          msg: "Entering main work loop",
          role: :pipeline_advancer,
          pipeline: klass
        )

        while running_context.running?
          id = Ductwork.wrap_with_app_executor do
            Ductwork::Pipeline
              .in_progress
              .where(klass: klass, claimed_for_advancing_at: nil)
              .where(steps: Ductwork::Step.where(status: :advancing))
              .where.not(steps: Ductwork::Step.where.not(status: %w[advancing completed]))
              .order(:last_advanced_at)
              .limit(1)
              .pluck(:id)
              .first
          end

          if id.present?
            rows_updated = Ductwork.wrap_with_app_executor do
              Ductwork::Pipeline
                .where(id: id, claimed_for_advancing_at: nil)
                .update_all(
                  claimed_for_advancing_at: Time.current,
                  status: "advancing"
                )
            end

            if rows_updated == 1
              Ductwork.logger.debug(
                msg: "Pipeline claimed",
                pipeline_id: id,
                pipeline: klass,
                role: :pipeline_advancer
              )

              @pipeline = Ductwork.wrap_with_app_executor do
                @pipeline = Ductwork::Pipeline.find(id)
                pipeline.advance!

                Ductwork.logger.debug(
                  msg: "Pipeline advanced",
                  pipeline_id: id,
                  pipeline: klass,
                  role: :pipeline_advancer
                )

                # rubocop:todo Metrics/BlockNesting
                status = pipeline.completed? ? "completed" : "in_progress"
                # rubocop:enable Metrics/BlockNesting
              ensure
                # release the pipeline and set last advanced at so it doesn't
                # block. we're not using a queue so we have to use a db
                # timestamp
                pipeline.update!(
                  claimed_for_advancing_at: nil,
                  last_advanced_at: Time.current,
                  status: status || "in_progress"
                )
              end
            else
              Ductwork.logger.debug(
                msg: "Did not claim pipeline, avoided race condition",
                pipeline_id: id,
                pipeline: klass,
                role: :pipeline_advancer
              )
            end
          else
            Ductwork.logger.debug(
              msg: "No pipeline needs advancing",
              pipeline: klass,
              role: :pipeline_advancer
            )
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
