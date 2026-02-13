# frozen_string_literal: true

class CreateDuctworkSteps < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_steps do |table|
      belongs_to(
        table,
        :pipeline,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_pipelines }
      )
      table.string :node, null: false
      table.string :klass, null: false
      table.string :to_transition, null: false
      table.timestamp :started_at
      table.timestamp :completed_at
      table.string :status, null: false
      table.integer :delay_seconds
      table.integer :timeout_seconds
      table.timestamps null: false
    end

    add_index :ductwork_steps, %i[pipeline_id status node]
    add_index :ductwork_steps, %i[pipeline_id node status]
    add_index :ductwork_steps, %i[status node]
    add_index :ductwork_steps, %i[pipeline_id status]
  end
end
