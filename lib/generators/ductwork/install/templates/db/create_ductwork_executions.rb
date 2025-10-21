# frozen_string_literal: true

class CreateDuctworkExecutions < ActiveRecord::Migration[7.0]
  def change
    create_table :ductwork_executions do |table|
      table.belongs_to :job, index: true, null: false, foreign_key: { to_table: :ductwork_jobs }
      table.timestamp :started_at, null: false
      table.timestamp :completed_at
      table.integer :process_id
      table.timestamps null: false
    end
  end
end
