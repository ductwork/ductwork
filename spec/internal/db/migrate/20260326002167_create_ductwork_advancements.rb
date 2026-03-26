# frozen_string_literal: true

class CreateDuctworkAdvancements < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_advancements do |table|
      belongs_to(
        table,
        :process,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_processes }
      )
      belongs_to(
        table,
        :transition,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_transitions }
      )
      table.datetime :started_at, null: false
      table.datetime :completed_at
      table.string :error_klass
      table.string :error_message
      table.text :error_backtrace
      table.timestamps null: false
    end
  end
end
