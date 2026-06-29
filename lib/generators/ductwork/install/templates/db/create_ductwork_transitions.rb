# frozen_string_literal: true

class CreateDuctworkTransitions < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_transitions do |table|
      belongs_to(
        table,
        :branch,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_branches }
      )
      belongs_to(
        table,
        :in_step,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_steps }
      )
      belongs_to(
        table,
        :out_step,
        index: true,
        null: true,
        foreign_key: { to_table: :ductwork_steps }
      )
      table.datetime :started_at, null: false
      table.datetime :completed_at
      table.timestamps null: false
    end

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
