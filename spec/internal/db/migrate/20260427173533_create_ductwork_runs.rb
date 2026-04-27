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

    if mysql?
      reversible do |direction|
        direction.up do
          execute <<~SQL
            ALTER TABLE ductwork_runs
              ADD COLUMN active_pipeline_id VARCHAR(36)
                GENERATED ALWAYS AS (
                  IF(status IN ('in_progress', 'paused'), pipeline_id, NULL)
                )
          SQL
          add_index :ductwork_runs, :active_pipeline_id,
                    unique: true,
                    name: :idx_unique_active_run
        end

        direction.down do
          remove_index :ductwork_runs, name: :idx_unique_active_run
          remove_column :ductwork_runs, :active_pipeline_id
        end
      end
    else
      add_index :ductwork_runs,
                :pipeline_id,
                unique: true,
                where: "status IN ('in_progress', 'paused')",
                name: :idx_unique_active_run
    end
  end
end
