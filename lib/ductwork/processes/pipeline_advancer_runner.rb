# frozen_string_literal: true

module Ductwork
  module Processes
    class PipelineAdvancerRunner
      def initialize(*klasses)
        @klasses = klasses
        @running_context = Ductwork::RunningContext.new

        Signal.trap(:INT) { running_context.shutdown! }
        Signal.trap(:TERM) { running_context.shutdown! }
        Signal.trap(:TTIN) do
          Thread.list.each do |thread|
            puts thread.name
            if thread.backtrace
              puts thread.backtrace.join("\n")
            else
              puts "No backtrace to dump"
            end
            puts
          end
        end
      end

      def run
        run_hooks_for(:start)
        create_process!
        logger.debug(msg: "Entering main work loop", role: :pipeline_advancer)

        while running_context.running?
          advance_all_pipelines
          report_heartbeat!
          sleep(Ductwork.configuration.pipeline_polling_timeout)
        end

        shutdown
      end

      private

      attr_reader :klasses, :running_context

      def create_process!
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.create!(
            pid: ::Process.pid,
            machine_identifier: Ductwork::MachineIdentifier.fetch,
            last_heartbeat_at: Time.current
          )
        end
      end

      def advance_all_pipelines
        Ductwork::Processes::PipelineAdvancer
          .new(running_context, *klasses)
          .call
      end

      def report_heartbeat!
        logger.debug(msg: "Reporting heartbeat", role: :pipeline_advancer)
        Ductwork.wrap_with_app_executor do
          Ductwork::Process.report_heartbeat!
        end
        logger.debug(msg: "Reported heartbeat", role: :pipeline_advancer)
      end

      def shutdown
        logger.debug(msg: "Shutting down", role: :pipeline_advancer)

        Ductwork.wrap_with_app_executor do
          Ductwork::Process.find_by!(
            pid: ::Process.pid,
            machine_identifier: Ductwork::MachineIdentifier.fetch
          ).delete
        end

        logger.debug(msg: "Process deleted", role: :pipeline_advancer)

        run_hooks_for(:stop)
      end

      def run_hooks_for(event)
        Ductwork.hooks[:advancer].fetch(event, []).each do |block|
          block.call(self)
        end
      end

      def logger
        Ductwork.configuration.logger
      end
    end
  end
end
