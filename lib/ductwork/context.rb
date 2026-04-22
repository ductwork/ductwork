# frozen_string_literal: true

module Ductwork
  class Context
    class OverwriteError < StandardError; end

    def initialize(run_id)
      @run_id = run_id
    end

    def get(key)
      raise ArgumentError, "Key must be a string" if !key.is_a?(String)

      Ductwork.wrap_with_app_executor do
        Ductwork::Tuple
          .select(:serialized_value)
          .find_by(run_id:, key:)
          &.value
      end
    end

    def set(key, value, overwrite: false)
      attributes = {
        id: SecureRandom.uuid_v7,
        run_id: run_id,
        key: key,
        serialized_value: Ductwork::Tuple.serialize(value),
        first_set_at: Time.current,
        last_set_at: Time.current,
      }
      opts = if Ductwork::Tuple.connection.adapter_name.match?(/mysql/i)
               {}
             else
               { unique_by: %i[run_id key] }
             end

      if overwrite
        Ductwork.wrap_with_app_executor do
          Ductwork::Tuple.upsert(attributes, **opts)
        end
      else
        Ductwork.wrap_with_app_executor do
          Ductwork::Tuple.create!(attributes)
        rescue ActiveRecord::RecordNotUnique
          raise Ductwork::Context::OverwriteError, "Can only set value once"
        end
      end

      value
    end

    private

    attr_reader :run_id
  end
end
