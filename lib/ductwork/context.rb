# frozen_string_literal: true

module Ductwork
  class Context
    class OverwriteError < StandardError; end

    def initialize(pipeline_id)
      @pipeline_id = pipeline_id
    end

    def get(key)
      raise ArgumentError, "Key must be a string" if !key.is_a?(String)

      Ductwork.wrap_with_app_executor do
        Ductwork::Tuple
          .select(:serialized_value)
          .find_by(pipeline_id:, key:)
          &.value
      end
    end

    def set(key, value, overwrite: false)
      attributes = {
        id: SecureRandom.uuid_v7,
        pipeline_id: pipeline_id,
        key: key,
        serialized_value: Ductwork::Tuple.serialize(value),
        first_set_at: Time.current,
        last_set_at: Time.current,
      }
      unique_by = %i[pipeline_id key]

      if overwrite
        Ductwork.wrap_with_app_executor do
          Ductwork::Tuple.upsert(attributes, unique_by:)
        end
      else
        result = Ductwork.wrap_with_app_executor do
          Ductwork::Tuple.insert(attributes, unique_by:)
        end

        if result.rows.none?
          raise Ductwork::Context::OverwriteError, "Can only set value once"
        end
      end

      value
    end

    private

    attr_reader :pipeline_id
  end
end
