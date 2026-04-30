# frozen_string_literal: true

class AddCrashCountToDuctworkExecutions < Ductwork::Migration
  def change
    add_column :ductwork_executions, :crash_count, :integer

    # NOTE: change this how you see fit for your scale
    Ductwork::Execution
      .where(crash_count: nil)
      .update_all(crash_count: 0)

    change_column_null :ductwork_executions, :crash_count, false
  end
end
