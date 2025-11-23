# frozen_string_literal: true

class CreateDuctworkSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :ductwork_steps do |table|
      table.belongs_to :pipeline, index: true, null: false, foreign_key: { to_table: :ductwork_pipelines }
      table.string :klass, null: false
      table.string :step_type, null: false
      table.timestamp :started_at
      table.timestamp :completed_at
      table.string :status, null: false
      table.timestamps null: false
    end

    add_index :ductwork_steps, %i[pipeline_id status]
  end
end
