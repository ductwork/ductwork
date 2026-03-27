# frozen_string_literal: true

class UpdateProcessAssociations < Ductwork::Migration
  def change
    remove_column :ductwork_availabilities, :process_id, :integer

    options = if postgresql?
                {
                  type: uuid_column_type,
                  index: true,
                  null: true,
                  foreign_key: { to_table: :ductwork_processes },
                }
              else
                {
                  type: uuid_column_type,
                  limit: 36,
                  index: true,
                  null: true,
                  foreign_key: { to_table: :ductwork_processes },
                }
              end

    add_reference :ductwork_availabilities, :process, **options
    add_index :ductwork_availabilities, %i[id process_id]

    remove_column :ductwork_executions, :process_id, :integer
  end
end
