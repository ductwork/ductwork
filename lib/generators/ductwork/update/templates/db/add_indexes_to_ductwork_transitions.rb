# frozen_string_literal: true

class AddIndexesToDuctworkTransitions < Ductwork::Migration
  def change
    if mysql?
      add_index :ductwork_transitions,
                %i[branch_id completed_at started_at],
                name: "index_ductwork_transitions_on_latest_open"
    else
      add_index :ductwork_transitions,
                %i[branch_id started_at],
                where: "completed_at IS NULL",
                name: "index_ductwork_transitions_on_latest_open"
    end
  end
end
