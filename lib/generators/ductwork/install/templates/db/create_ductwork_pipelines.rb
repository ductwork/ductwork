# frozen_string_literal: true

class CreateDuctworkPipelines < ActiveRecord::Migration[<%= Rails::VERSION::MAJOR %>.<%= Rails::VERSION::MINOR %>]
  def change
    create_table :ductwork_pipelines do |table|
      table.string :klass, null: false
      table.string :definition, null: false
      table.string :definition_sha1, null: false
      table.timestamp :triggered_at, null: false
      table.timestamp :completed_at
      table.timestamp :claimed_for_advancing_at
      table.string :status, null: false
      table.timestamps null: false
    end

    add_index :ductwork_pipelines, :klass
  end
end
