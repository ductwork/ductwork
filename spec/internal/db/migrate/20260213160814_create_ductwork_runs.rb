# frozen_string_literal: true

class CreateDuctworkRuns < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_runs do |table|
      belongs_to(
        table,
        :execution,
        index: false,
        null: false,
        foreign_key: { to_table: :ductwork_executions }
      )
      table.timestamp :started_at, null: false
      table.timestamp :completed_at
      table.timestamps null: false
    end

    add_index :ductwork_runs, :execution_id, unique: true
  end
end
