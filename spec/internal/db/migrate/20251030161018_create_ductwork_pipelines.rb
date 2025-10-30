# frozen_string_literal: true

class CreateDuctworkPipelines < ActiveRecord::Migration[7.0]
  def change
    create_table :ductwork_pipelines do |table|
      table.string :klass, null: false
      table.string :definition, null: false
      table.string :definition_sha1, null: false
      table.timestamp :triggered_at, null: false
      table.timestamp :completed_at
      table.string :status, null: false
    end

    add_index :ductwork_pipelines, :klass
  end
end
