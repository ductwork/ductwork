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
      process = current

      if process.present?
        process.update!(last_heartbeat_at: Time.current)
        process
      else
        Ductwork.logger.warn(
          msg: "Process record missing, re-adopting (likely reaped after host suspend)",
          pid: ::Process.pid
        )
        adopt_or_create_current!
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

        return if last_heartbeat_at > REAP_THRESHOLD.ago

        advancements.where(completed_at: nil).find_each do |advancement|
          advancement.transition.branch.release!
        end
        incomplete_executions = Ductwork::Execution.where(completed_at: nil)
        availabilities.joins(:execution).merge(incomplete_executions).find_each do |availability|
          availability.execution.job.execution_crashed!(availability.execution)
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
