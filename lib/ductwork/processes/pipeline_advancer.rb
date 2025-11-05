# frozen_string_literal: true

module Ductwork
  module Processes
    class PipelineAdvancer
      def initialize(running_context, *klasses)
        @running_context = running_context
        @klasses = klasses
      end

      def call # rubocop:disable Metrics
        logger.debug(msg: "Advancing pipelines", role: :pipeline_advancer)

        steps_to_advance.find_each do |step| # rubocop:disable Metrics/BlockLength
          break if !running_context.running?

          pipeline = step.pipeline
          definition = JSON.parse(pipeline.definition).with_indifferent_access
          edge = definition.dig(:edges, step.klass, 0)
          # should this be here or in a transaction somewhere
          # -> will prob need to rethink this algorithm so theres atomocity maybs?
          step.update!(status: :completed, completed_at: Time.current)

          if edge.nil?
            if !pipeline.steps.where.not(status: :completed).exists?
              pipeline.update!(status: "completed", completed_at: Time.current)
            end
          else
            type = edge[:type] == "chain" ? "default" : edge[:type]
            to = edge[:to]

            if type.in?(%w[default divide])
              to.each do |klass|
                next_step = pipeline.steps.create!(
                  klass: klass,
                  status: :in_progress,
                  step_type: type,
                  started_at: Time.current
                )
                payload = step.job.output_payload
                input_arg = if payload.present?
                              JSON.parse(payload).fetch("payload", nil)
                            end

                Ductwork::Job.enqueue(next_step, input_arg)
              end
            elsif type == "combine"
              previous_klasses = definition[:edges].select do |_, v|
                v.dig(0, :to, 0) == to.sole && v.dig(0, :type) == "combine"
              end.keys

              if pipeline.steps.not_completed.where(klass: previous_klasses).none?
                input_arg = Job.where(
                  step: pipeline.steps.completed.where(klass: previous_klasses)
                ).pluck(:output_payload).map do |payload|
                  JSON.parse(payload)["payload"]
                end
                next_step = pipeline.steps.create!(
                  klass: to.sole,
                  status: :in_progress,
                  step_type: type,
                  started_at: Time.current
                )

                Ductwork::Job.enqueue(next_step, input_arg)
              end
            elsif type == "expand"
              klass = to.sole
              payload = JSON.parse(step.job.output_payload)["payload"]

              payload.each do |input_arg|
                next_step = pipeline.steps.create!(
                  klass: klass,
                  status: :in_progress,
                  step_type: type,
                  started_at: Time.current
                )
                Ductwork::Job.enqueue(next_step, input_arg)
              end
            elsif type == "collapse"
              if pipeline.steps.not_completed.where(klass: step.klass).none?
                input_arg = Job.where(
                  step: pipeline.steps.completed.where(klass: step.klass)
                ).pluck(:output_payload).map do |payload|
                  JSON.parse(payload)["payload"]
                end

                next_step = pipeline.steps.create!(
                  klass: to.sole,
                  status: :in_progress,
                  step_type: type,
                  started_at: Time.current
                )
                Ductwork::Job.enqueue(next_step, input_arg)
              else
                logger.debug(msg: "Not all expanded steps have completed", role: :pipeline_advancer)
              end
            else
              logger.error("Invalid step type? This is wrong lol", role: :pipeline_advancer)
            end
          end
        end

        logger.debug(msg: "Advanced pipelines", role: :pipeline_advancer)
      end

      private

      attr_reader :running_context, :klasses

      def steps_to_advance
        Ductwork::Step
          .advancing
          .joins(:pipeline)
          .where(ductwork_pipelines: { klass: klasses })
      end

      def logger
        Ductwork.configuration.logger
      end
    end
  end
end
