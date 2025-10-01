# frozen_string_literal: true

class CreateDuctworkStepExecutions < ActiveRecord::Migration[7.0]
  def change
    create_table :ductwork_step_executions do |table|
      table.belongs_to :step, index: true, null: false, foreign_key: { to_table: :ductwork_steps }
      table.json :return_value
      table.timestamp :enqueued_at, null: false
      table.timestamp :advancing_at
      table.timestamp :completed_at
    end

    add_index :ductwork_step_executions, :jid, unique: true
  end
end
