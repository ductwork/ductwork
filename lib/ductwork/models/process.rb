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
    has_many :executions,
             class_name: "Ductwork::Execution",
             foreign_key: "process_id",
             dependent: :nullify

    validates :pid, uniqueness: { scope: :machine_identifier }

    enum :role,
         supervisor: "supervisor",
         pipeline_advancer: "pipeline_advancer",
         job_worker: "job_worker"

    def self.adopt_or_create_current!(role)
      pid = ::Process.pid
      machine_identifier = Ductwork::MachineIdentifier.fetch
      last_heartbeat_at = Ductwork::DatabaseClock.now
      existing = Ductwork::Process.find_by(pid:, machine_identifier:)

      if existing.present? && !existing.healthy?
        existing.reap!(role)
      end

      Ductwork::Process
        .find_or_initialize_by(pid:, machine_identifier:)
        .tap { |process| process.update!(last_heartbeat_at:, role:) }
    end

    def self.current
      pid = ::Process.pid
      machine_identifier = Ductwork::MachineIdentifier.fetch

      find_by(pid:, machine_identifier:)
    end

    def self.reap_all!(role)
      count = 0
      timeout = Ductwork.configuration.supervisor_reaper_timeout
      sql = Ductwork::DatabaseClock.ago_sql("last_heartbeat_at", timeout)

      Ductwork.logger.debug(
        msg: "Reaping orphaned process records",
        role: role
      )

      where(sql).find_each do |process|
        process.reap!(role)
        count += 1
      end

      Ductwork.logger.debug(
        msg: "Reaped #{count} orphaned process records",
        count: count,
        role: role
      )
    end

    def self.report_heartbeat!(role)
      process = current

      if process.present?
        process.update!(last_heartbeat_at: Ductwork::DatabaseClock.now)
        process
      else
        Ductwork.logger.warn(
          msg: "Process record missing, re-adopting (likely reaped after host suspend)",
          pid: ::Process.pid
        )
        adopt_or_create_current!(role)
      end
    end

    def reap!(role, force: false)
      timeout = Ductwork.configuration.supervisor_reaper_timeout
      sql = Ductwork::DatabaseClock.ago_sql("last_heartbeat_at", timeout)

      Ductwork.logger.debug(
        msg: "Reaping orphaned process record #{id}",
        id: id,
        role: role
      )

      Ductwork::Record.transaction do
        # NOTE: Callers that have already killed/stopped the process hold proof
        # of death and pass force: true to skip the staleness guard. The row
        # lock and existence check are kept either way to stay atomic and to
        # avoid double-reaping a record another parent already cleaned up
        scope = Ductwork::Process.where(id:).lock
        scope = scope.where(sql) unless force

        return unless scope.exists?

        advancements.where(completed_at: nil).find_each(&:process_crashed!)
        executions.where(completed_at: nil).find_each(&:crashed!)
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

    def healthy?
      timeout = Ductwork.configuration.supervisor_reaper_timeout
      sql = Ductwork::DatabaseClock.ago_sql("last_heartbeat_at", timeout)

      self.class.where(id:).where(sql).none?
    end
  end
end
