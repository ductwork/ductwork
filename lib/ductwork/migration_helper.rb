# frozen_string_literal: true

module Ductwork
  module MigrationHelper
    class OpenTransactionError < StandardError; end

    AVAILABILITY_CLAIM_INDEX_NAME = "index_ductwork_availabilities_on_claim_latest"
    AVAILABILITY_CLAIM_INDEX_NAME_V2 = "index_ductwork_availabilities_on_claim_latest_v2"
    AVAILABILITY_CLAIM_INDEX_NAMES = [
      AVAILABILITY_CLAIM_INDEX_NAME,
      AVAILABILITY_CLAIM_INDEX_NAME_V2,
    ].freeze

    def add_availability_claim_index(
      extra_columns: [],
      where_extra: nil,
      name: AVAILABILITY_CLAIM_INDEX_NAME,
      online: false
    )
      if mysql?
        columns = [:pipeline_klass, :completed_at, *extra_columns, :started_at]
        options = { name: }
      else
        columns = %i[pipeline_klass started_at]
        options = {
          name: name,
          where: ["completed_at IS NULL", where_extra].compact.join(" AND "),
        }
      end

      if online
        add_index_online :ductwork_availabilities, columns, **options
      else
        add_index :ductwork_availabilities, columns, **options
      end
    end

    def remove_availability_claim_index(name: AVAILABILITY_CLAIM_INDEX_NAME)
      remove_index :ductwork_availabilities, name: name, if_exists: true
    end

    def swap_availability_claim_index(to:, extra_columns: [], where_extra: nil)
      unless AVAILABILITY_CLAIM_INDEX_NAMES.include?(to)
        raise ArgumentError, "unrecognized availability claim index name: #{to}"
      end

      add_availability_claim_index(
        extra_columns: extra_columns,
        where_extra: where_extra,
        name: to,
        online: true
      )

      (AVAILABILITY_CLAIM_INDEX_NAMES - [to]).each do |stale|
        remove_index_online :ductwork_availabilities, name: stale
      end
    end

    def add_index_online(table_name, column_names, **options)
      ensure_ddl_transaction_disabled!

      name = options[:name] || connection.index_name(table_name, column_names)

      drop_invalid_index(table_name, name)

      return if connection.index_name_exists?(table_name, name)

      full_options = options.merge(name:)
      full_options[:algorithm] = :concurrently if postgresql?

      add_index table_name, column_names, **full_options
    end

    def remove_index_online(table_name, name:)
      ensure_ddl_transaction_disabled!

      return unless connection.index_name_exists?(table_name, name)

      options = { name: name, if_exists: true }
      options[:algorithm] = :concurrently if postgresql?

      remove_index table_name, **options
    end

    def drop_invalid_index(table_name, index_name)
      return unless postgresql?

      invalid = connection.select_value(<<~SQL.squish)
        SELECT 1 FROM pg_index
        WHERE indexrelid = to_regclass(#{connection.quote(index_name)})
          AND NOT indisvalid
      SQL

      return if invalid.blank?

      remove_index table_name,
                   name: index_name,
                   algorithm: :concurrently,
                   if_exists: true
    end

    def ensure_ddl_transaction_disabled!
      return unless postgresql?
      return unless connection.transaction_open?

      raise OpenTransactionError, <<~MESSAGE.squish
        online index changes cannot run inside a transaction on PostgreSQL;
        declare `disable_ddl_transaction!` in the migration
      MESSAGE
    end

    def create_ductwork_table(table_name, &block)
      if postgresql?
        create_table table_name, id: :uuid, &block
      else
        create_table table_name, id: false do |table|
          table.string :id, limit: 36, null: false, primary_key: true
          block.call(table)
        end
      end
    end

    def belongs_to(table_object, association_name, **options)
      full_options = if postgresql?
                       { type: uuid_column_type }.merge(options)
                     else
                       { type: uuid_column_type, limit: 36 }.merge(options)
                     end

      table_object.belongs_to association_name, **full_options
    end

    def uuid_column_type
      if postgresql?
        :uuid
      else
        :string
      end
    end

    def postgresql?
      connection.adapter_name.match?(/postgresql/i)
    end

    def mysql?
      connection.adapter_name.match?(/mysql|trilogy/i)
    end
  end
end
