# frozen_string_literal: true

class CreateDuctworkJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :ductwork_jobs do |table|
      table.belongs_to :step, index: false, null: false, foreign_key: { to_table: :ductwork_steps }
      table.string :klass, null: false
      table.timestamp :started_at, null: false
      table.timestamp :completed_at
      table.text :input_args, null: false
      table.text :output_payload
      table.timestamps null: false
    end

    add_index :ductwork_jobs, :step_id, unique: true
  end
end
