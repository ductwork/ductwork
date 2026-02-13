# frozen_string_literal: true

module Ductwork
  module MigrationHelper
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
      connection.adapter_name.match?(/mysql/i)
    end
  end
end
