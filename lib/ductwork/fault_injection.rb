# frozen_string_literal: true

module Ductwork
  module FaultInjection
    ENV_KEY = "DUCTWORK_FAULT"

    class << self
      def checkpoint(key)
        return if !ENV.key?(ENV_KEY)

        spec = ENV.fetch(ENV_KEY, "").split(":")

        return if spec[0] != key.to_s

        warn "FAULT FIRING: #{spec[0]} -> #{spec[1]} (pid=#{::Process.pid})"

        case spec[1]
        when "kill" then ::Process.kill(:KILL, ::Process.pid)
        when "raise" then raise "FaultInjection: #{key}"
        when "sleep" then sleep(1)
        when "exit" then exit!(1)
        end
      end

      def with(key, action)
        previous_value = ENV.fetch(ENV_KEY, nil)
        ENV[ENV_KEY] = "#{key}:#{action}"

        yield
      ensure
        ENV[ENV_KEY] = previous_value
      end
    end
  end
end
