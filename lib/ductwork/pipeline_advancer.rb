# frozen_string_literal: true

module Ductwork
  class PipelineAdvancer
    def initialize(*klasses)
      @klasses = klasses
      @running = true

      Signal.trap(:INT) { @running = false }
      Signal.trap(:TERM) { @running = false }
    end

    def run
      create_process!
      logger.debug(msg: "Entering main work loop", role: :pipeline_advancer)

      while running
        advance_all_pipelines
        report_heartbeat!
        sleep(1)
      end

      shutdown
    end

    def advance_all_pipelines
      logger.debug(msg: "Advancing all pipelines", role: :pipeline_advancer)

      pipelines.find_each do |_pipeline|
        break if !running

        # 1. Query all other `steps` records in the same Stage/Branch
        # 2. If all steps are status "advancing", continue.
        #      Otherwise, Stage is not ready to advance
        # 3. Check if any `steps.job` has failed:
        #      If not, continue.
        #      If yes, halt pipeline and log
        # 4. Mark all `steps` in Stage as "completed"
        # 5. Create next Stage and all `steps` with status "in-progress" from pipeline definition
      end

      logger.debug(msg: "Advanced all pipelines", role: :pipeline_advancer)
    end

    private

    attr_reader :klasses, :running

    def create_process!
      Ductwork::Process.create!(
        pid: ::Process.pid,
        machine_identifier: Ductwork::MachineIdentifier.fetch,
        last_heartbeat_at: Time.current
      )
    end

    def pipelines
      Ductwork::Pipeline
        .joins(:steps)
        .where(klass: klasses)
        .where(steps: { status: "advancing" })
        .distinct
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
