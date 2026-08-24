# frozen_string_literal: true

module Ductwork
  module MigrationHelper
    AVAILABILITY_CLAIM_INDEX_NAME = "index_ductwork_availabilities_on_claim_latest"

    def add_availability_claim_index(extra_columns: [], where_extra: nil)
      if mysql?
        add_index :ductwork_availabilities,
                  [:pipeline_klass, :completed_at, *extra_columns, :started_at],
                  name: AVAILABILITY_CLAIM_INDEX_NAME
      else
        predicate = ["completed_at IS NULL", where_extra].compact.join(" AND ")

        add_index :ductwork_availabilities,
                  %i[pipeline_klass started_at],
                  name: AVAILABILITY_CLAIM_INDEX_NAME,
                  where: predicate
      end
    end

    def remove_availability_claim_index
      remove_index :ductwork_availabilities,
                   name: AVAILABILITY_CLAIM_INDEX_NAME,
                   if_exists: true
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
