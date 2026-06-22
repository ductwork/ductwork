# frozen_string_literal: true

class CreateDuctworkTuples < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_tuples do |table|
      belongs_to(
        table,
        :run,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_runs }
      )
      table.string :key, null: false
      table.string :serialized_value
      table.datetime :first_set_at, null: false
      table.datetime :last_set_at, null: false
      table.timestamps null: false
    end

    add_index :ductwork_tuples, %i[run_id key], unique: true
  end
end
