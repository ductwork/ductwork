# frozen_string_literal: true

class CreateDuctworkSteps < ActiveRecord::Migration[<%= Rails::VERSION::MAJOR %>.<%= Rails::VERSION::MINOR %>]
  def change
    create_table :ductwork_steps do |table|
      table.belongs_to :pipeline, index: true, null: false, foreign_key: { to_table: :ductwork_pipelines }
      table.string :klass, null: false
      table.string :to_transition, null: false
      table.timestamp :started_at
      table.timestamp :completed_at
      table.string :status, null: false
      table.integer :delay_seconds
      table.integer :timeout_seconds
      table.timestamps null: false
    end

    add_index :ductwork_steps, %i[pipeline_id status klass]
    add_index :ductwork_steps, %i[pipeline_id klass status]
    add_index :ductwork_steps, %i[status klass]
    add_index :ductwork_steps, %i[pipeline_id status]
  end
end
