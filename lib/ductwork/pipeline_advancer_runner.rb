# frozen_string_literal: true

module Ductwork
  class PipelineAdvancerRunner
    def initialize(*klasses)
      @klasses = klasses
      @running_context = Ductwork::RunningContext.new

      Signal.trap(:INT) { running_context.shutdown! }
      Signal.trap(:TERM) { running_context.shutdown! }
    end

    def run
      create_process!
      logger.debug(msg: "Entering main work loop", role: :pipeline_advancer)

      while running_context.running?
        advance_all_pipelines!
        report_heartbeat!
        sleep(1)
      end

      shutdown
    end

    def advance_all_pipelines! # rubocop:disable Metrics
      logger.debug(msg: "Advancing pipelines", role: :pipeline_advancer)

      Ductwork::Step.advancing.find_each do |step| # rubocop:disable Metrics/BlockLength
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
              args = JSON.parse(step.job.output_payload)["payload"]

              Ductwork::Job.enqueue(next_step, args)
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

    attr_reader :klasses, :running_context

    def create_process!
      Ductwork::Process.create!(
        pid: ::Process.pid,
        machine_identifier: Ductwork::MachineIdentifier.fetch,
        last_heartbeat_at: Time.current
      )
    end

    def report_heartbeat!
      logger.debug(msg: "Reporting heartbeat", role: :pipeline_advancer)
      Ductwork::Process.report_heartbeat!
      logger.debug(msg: "Reported heartbeat", role: :pipeline_advancer)
    end

    def shutdown
      logger.debug(msg: "Shutting down", role: :pipeline_advancer)

      Ductwork::Process.find_by!(
        pid: ::Process.pid,
        machine_identifier: Ductwork::MachineIdentifier.fetch
      ).delete

      logger.debug(msg: "Process deleted", role: :pipeline_advancer)
    end

    def logger
      Ductwork.configuration.logger
    end
  end
end
