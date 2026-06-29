# frozen_string_literal: true

class AddPipelineStartedIndexToDuctworkRuns < Ductwork::Migration
  def change
    add_index :ductwork_runs, %i[pipeline_id started_at]
  end
end
