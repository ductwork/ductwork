# frozen_string_literal: true

module Ductwork
  class Process < Ductwork::Record
    has_many :advancements,
             class_name: "Ductwork::Advancement",
             foreign_key: "process_id",
             dependent: :destroy

    class NotFoundError < StandardError; end

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

      find_by!(pid:, machine_identifier:)
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Process #{pid} not found"
    end

    def self.report_heartbeat!
      current.update!(last_heartbeat_at: Time.current)
    end
  end
end
