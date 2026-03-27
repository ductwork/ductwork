# frozen_string_literal: true

module Ductwork
  class Process < Ductwork::Record
    has_many :advancements,
             class_name: "Ductwork::Advancement",
             foreign_key: "process_id",
             dependent: :nullify
    has_many :availabilities,
             class_name: "Ductwork::Availability",
             foreign_key: "process_id",
             dependent: :nullify

    REAP_THRESHOLD = 1.minute.freeze

    validates :pid, uniqueness: { scope: :machine_identifier }

    def self.adopt_or_create_current!
      pid = ::Process.pid
      machine_identifier = Ductwork::MachineIdentifier.fetch
      last_heartbeat_at = Time.current

      Ductwork::Process
        .find_or_initialize_by(pid:, machine_identifier:)
        .tap { |process| process.update!(last_heartbeat_at:) }
    end

    def self.current
      pid = ::Process.pid
      machine_identifier = Ductwork::MachineIdentifier.fetch

      find_by(pid:, machine_identifier:)
    end

    def self.reap_all!(role)
      count = 0

      Ductwork.logger.debug(
        msg: "Reaping orphaned process records",
        role: role
      )

      where("last_heartbeat_at < ?", REAP_THRESHOLD.ago).find_each do |process|
        process.reap!(role)
        count += 1
      end

      Ductwork.logger.debug(
        msg: "Reaped #{count} orphaned process records",
        count: count,
        role: role
      )
    end

    def self.report_heartbeat!
      current.tap do |process|
        if process.present?
          process.update!(last_heartbeat_at: Time.current)
        else
          Ductwork.logger.error(
            msg: "Process record missing, cannot report heartbeat",
            pid: ::Process.pid
          )
        end
      end
    end

    def reap!(role) # rubocop:todo Metrics/AbcSize
      Ductwork.logger.debug(
        msg: "Reaping orphaned process record #{id}",
        id: id,
        role: role
      )

      Ductwork::Record.transaction do
        lock!

        advancements.where(completed_at: nil).find_each do |advancement|
          advancement.transition.branch.release!
        end
        orphaned = availabilities.joins(:execution).merge(Ductwork::Execution.where(completed_at: nil))
        orphaned.find_each do |availability|
          execution = availability.execution
          job = execution.job
          pipeline = job.step.pipeline

          execution.update!(completed_at: Time.current)
          execution.run&.update!(completed_at: Time.current)
          execution.create_result!(result_type: "process_crashed")

          new_execution = job.executions.create!(
            retry_count: execution.retry_count,
            started_at: Ductwork::Job::FAILED_EXECUTION_TIMEOUT.from_now
          )
          new_execution.create_availability!(
            started_at: Ductwork::Job::FAILED_EXECUTION_TIMEOUT.from_now,
            pipeline_klass: pipeline.klass
          )
        end
        destroy
      end
      Ductwork.logger.debug(
        msg: "Reaped orphaned process record #{id}",
        id: id,
        role: role
      )
    rescue ActiveRecord::RecordNotFound
      Ductwork.logger.debug(
        msg: "Process already reaped by another parent",
        id: id,
        role: role
      )
    end
  end
end
