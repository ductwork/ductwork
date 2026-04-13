# frozen_string_literal: true

class CreateDuctworkBranchLinks < Ductwork::Migration
  def change
    create_ductwork_table :ductwork_branch_links do |table|
      belongs_to(
        table,
        :parent_branch,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_branches }
      )
      belongs_to(
        table,
        :child_branch,
        index: true,
        null: false,
        foreign_key: { to_table: :ductwork_branches }
      )
      table.timestamps null: false
    end

    add_index :ductwork_branch_links,
              %w[parent_branch_id child_branch_id],
              unique: true
  end
end
