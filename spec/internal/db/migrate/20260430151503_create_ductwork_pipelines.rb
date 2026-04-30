# frozen_string_literal: true

class CreateDuctworkPipelines < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_pipelines do |table|
      table.string :klass, null: false
      table.string :status, null: false
      table.timestamps null: false
    end

    add_index :ductwork_pipelines, :klass
  end
end
