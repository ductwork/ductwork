# frozen_string_literal: true

class AddIndexesToDuctworkRuns < Ductwork::Migration
  def change
    add_index :ductwork_runs, :started_at
    add_index :ductwork_runs, %i[pipeline_klass started_at]
    add_index :ductwork_runs, %i[status started_at]
  end
end
