# frozen_string_literal: true

module RuboCop
  module Cop
    module Ductwork
      # Checks that the availability claim index is never named directly.
      #
      # `index_ductwork_availabilities_on_claim_latest` is the only index
      # serving `Ductwork::RowLockingExecutionClaim#claim_availability`, the
      # hottest read in the system. Its shape differs by adapter -- a partial
      # index on PostgreSQL and SQLite, a leading `completed_at` column on
      # MySQL -- and `ductwork-pro` narrows it further to keep limited steps
      # off the unkeyed access path.
      #
      # A migration that writes the index by hand therefore has two ways to be
      # wrong, and both are silent. It can disagree with the canonical shape,
      # or it can drop and recreate the index by name and quietly discard a
      # narrowing some other gem installed. Nothing raises in either case; the
      # claim query just gets slower.
      #
      # `Ductwork::MigrationHelper` owns the definition. Use
      # `add_availability_claim_index` and `remove_availability_claim_index` to
      # build it, `swap_availability_claim_index` to change its shape without
      # ever leaving the table unindexed, and the
      # `AVAILABILITY_CLAIM_INDEX_NAME*` constants to refer to it.
      #
      # Every name the index has ever had is listed, not just the current one.
      # A migration that hand-writes a superseded name can drop an index some
      # other gem is relying on, which fails exactly as silently.
      #
      # The names are duplicated below rather than loaded from the helper
      # because cops are required by RuboCop in isolation, without the gem or
      # Rails loaded. The helper is excluded in `.rubocop.yml`.
      #
      # @example
      #   # bad
      #   add_index :ductwork_availabilities,
      #             %i[pipeline_klass started_at],
      #             name: "index_ductwork_availabilities_on_claim_latest",
      #             where: "completed_at IS NULL"
      #
      #   # bad
      #   remove_index :ductwork_availabilities,
      #                name: "index_ductwork_availabilities_on_claim_latest"
      #
      #   # good
      #   add_availability_claim_index
      #
      #   # good
      #   remove_availability_claim_index
      #
      #   # good
      #   connection.index_exists?(
      #     :ductwork_availabilities,
      #     name: Ductwork::MigrationHelper::AVAILABILITY_CLAIM_INDEX_NAME
      #   )
      class AvailabilityClaimIndex < Base
        MSG = "Do not name the availability claim index directly; " \
              "use `Ductwork::MigrationHelper`'s claim index helpers."

        INDEX_NAMES = %w[
          index_ductwork_availabilities_on_claim_latest
          index_ductwork_availabilities_on_claim_latest_v2
        ].freeze

        def on_str(node)
          return unless INDEX_NAMES.include?(node.value)

          add_offense(node)
        end

        def on_sym(node)
          return unless INDEX_NAMES.include?(node.value.to_s)

          add_offense(node)
        end
      end
    end
  end
end
