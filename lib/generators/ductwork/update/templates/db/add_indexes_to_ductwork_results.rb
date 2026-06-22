# frozen_string_literal: true

class AddIndexesToDuctworkResults < Ductwork::Migration
  def change
    add_index :ductwork_results, %i[result_type created_at]
  end
end
