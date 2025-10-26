# frozen_string_literal: true

module Ductwork
  class Process < Ductwork::Record
    class NotFoundError < StandardError; end

    validates :pid, uniqueness: { scope: :machine_identifier }

    def self.report_heartbeat!
      pid = ::Process.pid
      machine_identifier = Ductwork::MachineIdentifier.fetch

      find_by!(pid:, machine_identifier:)
        .update!(last_heartbeat_at: Time.current)
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Process #{pid} not found"
    end
  end
end
