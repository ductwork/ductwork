# frozen_string_literal: true

class CreateDuctworkAvailabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :ductwork_availabilities do |table|
      table.belongs_to :execution, index: false, null: false, foreign_key: { to_table: :ductwork_executions }
      table.timestamp :started_at, null: false
      table.timestamp :completed_at
      table.integer :process_id
      table.timestamps null: false
    end

    add_index :ductwork_availabilities, :execution_id, unique: true
    add_index :ductwork_availabilities, %i[id process_id]
  end
end
