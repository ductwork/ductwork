# frozen_string_literal: true

class AssociateStepsToRuns < Ductwork::Migration
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

    add_reference :ductwork_steps, :run, **options

    Ductwork::Pipeline.find_each do |pipeline|
      run = Ductwork::Run.find_by(pipeline_id: pipeline.id)
      pipeline.steps.update_all(run_id: run.id) if run
    end

    remove_index :ductwork_steps, %i[pipeline_id status node]
    remove_index :ductwork_steps, %i[pipeline_id node status]
    remove_index :ductwork_steps, %i[pipeline_id status]
    remove_reference :ductwork_steps, :pipeline, index: true, foreign_key: { to_table: :ductwork_pipelines }

    add_index :ductwork_steps, %i[run_id status node]
    add_index :ductwork_steps, %i[run_id node status]
    add_index :ductwork_steps, %i[run_id status]
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

    add_reference :ductwork_steps, :pipeline, **options

    Ductwork::Run.find_each do |run|
      Ductwork::Step.where(run_id: run.id).update_all(pipeline_id: run.pipeline_id)
    end

    remove_index :ductwork_steps, %i[run_id status node]
    remove_index :ductwork_steps, %i[run_id node status]
    remove_index :ductwork_steps, %i[run_id status]
    remove_reference :ductwork_steps, :run, index: true, foreign_key: { to_table: :ductwork_runs }

    add_index :ductwork_steps, %i[pipeline_id status node]
    add_index :ductwork_steps, %i[pipeline_id node status]
    add_index :ductwork_steps, %i[pipeline_id status]
  end
end
