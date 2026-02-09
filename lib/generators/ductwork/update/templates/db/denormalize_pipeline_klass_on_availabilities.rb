# frozen_string_literal: true

class DenormalizePipelineKlassOnAvailabilities < ActiveRecord::Migration[<%= Rails::VERSION::MAJOR %>.<%= Rails::VERSION::MINOR %>]
  def change
    add_column :ductwork_availabilities, :pipeline_klass, :string

    # NOTE: change this how you see fit. everything is updated to a static,
    # bogus value in case there are a lot of records.
    Ductwork::Availability
      .where(pipeline_klass: nil)
      .update_all(pipeline_klass: "Pipeline")

    change_column_null :ductwork_availabilities, :pipeline_klass, false
    remove_index :ductwork_availabilities, name: "index_ductwork_availabilities_on_claim_latest"
    add_index :ductwork_availabilities,
              %i[pipeline_klass completed_at started_at],
              name: "index_ductwork_availabilities_on_claim_latest"
  end
end
