# frozen_string_literal: true

class CreateDuctworkJobs < ActiveRecord::Migration[7.0]
  def change
    create_table :ductwork_jobs do |table|
      table.belongs_to :step, index: true, null: false, foreign_key: { to_table: :ductwork_steps }
      table.string :adapter, null: false
      table.string :jid, null: false
      table.string :status, null: false
      table.json :return_value
      table.timestamp :enqueued_at, null: false
      table.timestamp :completed_at
    end

    add_index :ductwork_jobs, :jid, unique: true
  end
end
