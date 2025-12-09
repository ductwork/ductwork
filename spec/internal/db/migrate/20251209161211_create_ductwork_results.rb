# frozen_string_literal: true

class CreateDuctworkResults < ActiveRecord::Migration[8.1]
  def change
    create_table :ductwork_results do |table|
      table.belongs_to :execution, index: false, null: false, foreign_key: { to_table: :ductwork_executions }
      table.string :result_type, null: false
      table.string :error_klass
      table.string :error_message
      table.text :error_backtrace
      table.timestamps null: false
    end

    add_index :ductwork_results, :execution_id, unique: true
  end
end
