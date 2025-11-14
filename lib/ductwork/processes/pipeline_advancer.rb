# frozen_string_literal: true

module Ductwork
  module Processes
    class PipelineAdvancer
      def initialize(running_context, klass)
        @running_context = running_context
        @klass = klass
      end

      def run # rubocop:todo Metrics/AbcSize, Metrics/MethodLength
        run_hooks_for(:start)
        while running_context.running?
          id = Ductwork::Pipeline
               .in_progress
               .where(klass:)
               .where.not(steps: Ductwork::Step.where.not(status: %w[advancing completed]))
               .order(:last_advanced_at)
               .limit(1)
               .pluck(:id)
               .first

          if id.present?
            rows_updated = Ductwork::Pipeline
                           .where(id: id, claimed_for_advancing_at: nil)
                           .update_all(claimed_for_advancing_at: Time.current)

            if rows_updated == 1
              logger.debug(
                msg: "Pipeline claimed",
                role: :pipeline_advancer
              )

              pipeline = Ductwork::Pipeline.find(id)
              pipeline.advance!

              logger.debug(
                msg: "Pipeline advanced",
                role: :pipeline_advancer
              )
            else
              logger.debug(
                msg: "Did not claim pipeline, avoided race condition",
                role: :pipeline_advancer
              )
            end

            # release the pipeline and set last advanced at so it doesnt block.
            # we're not using a queue so we have to use a db timestamp
            Ductwork::Pipeline
              .find(id)
              .update!(claimed_for_advancing_at: nil, last_advanced_at: Time.current)
          else
            logger.debug(
              msg: "No pipeline needs advancing",
              pipeline: klass,
              role: :pipeline_advancer
            )
          end

          sleep(Ductwork.configuration.pipeline_polling_timeout)
        end

        run_hooks_for(:stop)
      end

      private

      attr_reader :running_context, :klass

      def run_hooks_for(event)
        Ductwork.hooks[:advancer].fetch(event, []).each do |block|
          Ductwork.wrap_with_app_executor do
            block.call(self)
          end
        end
      end

      def logger
        Ductwork.configuration.logger
      end
    end
  end
end
