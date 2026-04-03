# frozen_string_literal: true

class CreateDuctworkRuns < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_runs do |table|
      belongs_to(
        table,
        :pipeline,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_pipelines }
      )
      table.string :pipeline_klass, null: false
      table.text :definition, null: false
      table.string :definition_sha1, null: false
      table.string :status, null: false
      table.datetime :triggered_at, null: false
      table.datetime :started_at, null: false
      table.datetime :completed_at
      table.datetime :halted_at
      table.timestamps null: false
    end

    add_index :ductwork_runs, %i[pipeline_id status]
    add_index :ductwork_runs,
              :pipeline_id,
              unique: true,
              where: "status = 'in_progress'",
              name: "index_ductwork_runs_on_one_in_progress_per_pipeline"
  end
end
