# frozen_string_literal: true

class AssociateBranchesToRuns < Ductwork::Migration
  def up
    options = if postgresql?
                {
                  type: uuid_column_type,
                  index: true,
                  null: true,
                  foreign_key: { to_table: :ductwork_runs },
                }
              else
                {
                  type: uuid_column_type,
                  limit: 36,
                  index: true,
                  null: true,
                  foreign_key: { to_table: :ductwork_runs },
                }
              end

    add_reference :ductwork_branches, :run, **options

    Ductwork::Pipeline.find_each do |pipeline|
      run = Ductwork::Run.create!(
        pipeline: pipeline,
        pipeline_klass: pipeline.klass,
        definition: pipeline.definition,
        definition_sha1: pipeline.definition_sha1,
        status: pipeline.status,
        triggered_at: pipeline.triggered_at,
        started_at: pipeline.started_at,
        completed_at: pipeline.completed_at,
        halted_at: pipeline.halted_at
      )
      pipeline.branches.update_all(run_id: run.id)
    end

    remove_index :ductwork_branches, %w[pipeline_id started_at]
    remove_reference :ductwork_branches, :pipeline, index: true, foreign_key: { to_table: :ductwork_pipelines }

    add_index :ductwork_branches, %w[run_id started_at]
  end

  def down
    options = if postgresql?
                {
                  type: uuid_column_type,
                  index: true,
                  null: true,
                  foreign_key: { to_table: :ductwork_pipelines },
                }
              else
                {
                  type: uuid_column_type,
                  limit: 36,
                  index: true,
                  null: true,
                  foreign_key: { to_table: :ductwork_pipelines },
                }
              end

    add_reference :ductwork_branches, :pipeline, **options

    Ductwork::Run.find_each do |run|
      Ductwork::Branch.where(run_id: run.id).update_all(pipeline_id: run.pipeline_id)
    end

    remove_index :ductwork_branches, %w[run_id started_at]
    remove_reference :ductwork_branches, :run, index: true, foreign_key: { to_table: :ductwork_runs }

    add_index :ductwork_branches, %w[pipeline_id started_at]
  end
end
