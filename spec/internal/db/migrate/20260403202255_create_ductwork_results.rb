# frozen_string_literal: true

class CreateDuctworkResults < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_results do |table|
      belongs_to(
        table,
        :execution,
        index: false,
        null: false,
        foreign_key: { to_table: :ductwork_executions }
      )
      table.string :result_type, null: false
      table.string :error_klass
      table.string :error_message
      table.text :error_backtrace
      table.timestamps null: false
    end

    add_index :ductwork_results, :execution_id, unique: true
  end
end
