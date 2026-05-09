# frozen_string_literal: true

class CreateDuctworkExecutions < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_executions do |table|
      belongs_to(
        table,
        :job,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_jobs }
      )
      belongs_to(
        table,
        :process,
        index: true,
        null: true,
        foreign_key: { to_table: :ductwork_processes }
      )
      table.timestamp :started_at, null: false
      table.timestamp :completed_at
      table.integer :retry_count, null: false
      table.integer :crash_count, null: false
      table.timestamps null: false
    end

    add_index :ductwork_executions, %i[job_id created_at]
  end
end
