# frozen_string_literal: true

class CreateDuctworkPipelineInstances < ActiveRecord::Migration[7.0]
  def change
    create_table :ductwork_pipeline_instances do |table|
      table.string :name, null: false
      table.timestamp :triggered_at, null: false
      table.timestamp :completed_at
      table.string :status, null: false
    end

    add_index :ductwork_pipeline_instances, :name, unique: true
  end
end
