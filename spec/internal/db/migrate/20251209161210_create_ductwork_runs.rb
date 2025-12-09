# frozen_string_literal: true

class CreateDuctworkRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :ductwork_runs do |table|
      table.belongs_to :execution, index: false, null: false, foreign_key: { to_table: :ductwork_executions }
      table.timestamp :started_at, null: false
      table.timestamp :completed_at
      table.timestamps null: false
    end

    add_index :ductwork_runs, :execution_id, unique: true
  end
end
