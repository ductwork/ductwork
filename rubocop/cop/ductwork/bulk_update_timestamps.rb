# frozen_string_literal: true

module RuboCop
  module Cop
    module Ductwork
      # Checks that `update_all` and `update_columns` set `updated_at`
      # explicitly.
      #
      # Both methods issue SQL directly and deliberately skip callbacks,
      # validations, and Active Record's timestamp handling. That is usually
      # the point -- they exist to express an atomic, conditional `UPDATE` --
      # but the skipped timestamp is rarely intentional. A row whose entire
      # post-insert lifecycle runs through them keeps the `updated_at` it was
      # inserted with forever, which silently breaks incremental replication
      # (`WHERE updated_at > cursor`), cache keys, and any operator trying to
      # answer "when did this row last change".
      #
      # `insert_all` and `upsert_all` are NOT flagged: since Rails 7.0 they
      # honor `record_timestamps` and populate both columns on their own.
      #
      # The cop only inspects hash literals. A hash built elsewhere and passed
      # in (`update_all(attrs)`), or one containing a double-splat, cannot be
      # checked statically and is left alone.
      #
      # @example
      #   # bad
      #   Execution.where(id: id).update_all(completed_at: Time.current)
      #
      #   # good
      #   completed_at = updated_at = Time.current
      #   Execution.where(id: id).update_all(completed_at:, updated_at:)
      #
      #   # good -- not statically checkable, ignored
      #   Execution.where(id: id).update_all(attrs)
      class BulkUpdateTimestamps < Base
        MSG = "`%<method>s` skips Active Record timestamps; set `updated_at` explicitly."

        RESTRICT_ON_SEND = %i[update_all update_columns].freeze

        def on_send(node)
          attributes = node.first_argument

          return unless attributes&.hash_type?
          # a `**splat` may carry `updated_at`, so the hash is not decidable
          return unless attributes.children.all?(&:pair_type?)
          return if stamps_updated_at?(attributes)

          add_offense(node.loc.selector, message: format(MSG, method: node.method_name))
        end

        private

        def stamps_updated_at?(hash_node)
          hash_node.pairs.any? do |pair|
            pair.key.sym_type? && pair.key.value == :updated_at
          end
        end
      end
    end
  end
end
