# frozen_string_literal: true

module Ductwork
  class MachineIdentifier
    def self.fetch
      File.read("/etc/machine-id").strip
    rescue Errno::ENOENT
      Socket.gethostname
    end
  end
end
