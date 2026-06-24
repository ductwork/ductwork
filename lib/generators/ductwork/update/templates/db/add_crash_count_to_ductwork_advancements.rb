# frozen_string_literal: true

class AddCrashCountToDuctworkAdvancements < Ductwork::Migration
  def change
    add_column :ductwork_advancements, :crash_count, :integer
  end
end
