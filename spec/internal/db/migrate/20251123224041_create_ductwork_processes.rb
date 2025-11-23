# frozen_string_literal: true

class CreateDuctworkProcesses < ActiveRecord::Migration[8.1]
  def change
    create_table :ductwork_processes do |table|
      table.integer :pid, null: false
      table.string :machine_identifier, null: false
      table.timestamp :last_heartbeat_at, null: false
      table.timestamps null: false
    end

    add_index :ductwork_processes, %i[pid machine_identifier], unique: true
  end
end
