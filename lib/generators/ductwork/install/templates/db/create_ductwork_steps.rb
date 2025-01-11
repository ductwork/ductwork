# frozen_string_literal: true

class CreateDuctworkSteps < ActiveRecord::Migration[7.0]
  def change
    create_table :ductwork_steps do |table|
      table.belongs_to :pipeline, index: true, null: false, foreign_key: { to_table: :ductwork_pipelines }
      table.belongs_to :next_step, index: true, foreign_key: { to_table: :ductwork_steps }
      table.string :step_type, null: false
      table.string :klass, null: false
      table.timestamp :started_at
      table.timestamp :completed_at
    end
  end
end
