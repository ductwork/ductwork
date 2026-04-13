# frozen_string_literal: true

class CreateDuctworkBranches < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_branches do |table|
      belongs_to(
        table,
        :pipeline,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_pipelines }
      )
      table.string :pipeline_klass, null: false
      table.string :status, null: false
      table.string :halt_reason
      table.datetime :claimed_for_advancing_at
      table.datetime :last_advanced_at, null: false
      table.datetime :started_at, null: false
      table.datetime :completed_at
      table.timestamps null: false
    end

    add_index :ductwork_branches,
              %w[pipeline_klass claimed_for_advancing_at last_advanced_at],
              name: "index_ductwork_branches_on_claim_latest"
    add_index :ductwork_branches, %w[pipeline_id started_at]
  end
end
