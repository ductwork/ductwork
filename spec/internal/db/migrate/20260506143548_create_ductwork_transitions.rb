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
  end
end
