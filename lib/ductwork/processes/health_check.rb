# frozen_string_literal: true

module Ductwork
  module Processes
    class HealthCheck
      def self.run(**)
        new(**).run
      end

      def initialize(pid: nil, verbose: false)
        @pid = pid
        @machine_identifier = Ductwork::MachineIdentifier.fetch
        @verbose = verbose
      end

      def run
        exit_code = supervisor_processes.reduce(0) do |acc, process|
          if process.healthy?
            puts_healthy(process)
            acc
          else
            puts_unhealthy(process)
            acc + 1
          end
        end

        if pid.present? && supervisor_processes.none?
          puts_dead
          exit_code = 1
        end

        exit(exit_code)
      end

      private

      attr_reader :pid, :machine_identifier, :verbose

      def supervisor_processes
        Ductwork::Process.supervisors.then do |relation|
          if pid.present?
            relation.where(pid:, machine_identifier:)
          else
            relation
          end
        end
      end

      def puts_dead
        if verbose
          puts <<~STDOUT
            PID #{pid} (#{machine_identifier})
              Status: dead
          STDOUT
        else
          puts "dead"
        end
      end

      def puts_healthy(process)
        if verbose
          puts_verbose(process, "healthy")
        else
          puts "healthy"
        end
      end

      def puts_unhealthy(process)
        if verbose
          puts_verbose(process, "unhealthy")
        else
          puts "unhealthy"
        end
      end

      def puts_verbose(process, status)
        puts <<~STDOUT
          PID #{process.pid} (#{process.machine_identifier})
            ID: #{process.id}
            Created At: #{process.created_at.iso8601}
            Last Heartbeat At: #{process.last_heartbeat_at.iso8601}
            Status: #{status}
        STDOUT
      end
    end
  end
end
