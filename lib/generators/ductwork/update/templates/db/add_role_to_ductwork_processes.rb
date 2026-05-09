# frozen_string_literal: true

class AddRoleToDuctworkProcesses < Ductwork::Migration
  def up
    add_column :ductwork_processes, :role, :string

    # NOTE: ideally there are no process records that exist because the
    # ductwork process should not be running. either way, we explicitly
    # don't set it to supervisor so it won't report in the health checks
    Ductwork::Process
      .where(role: nil)
      .update_all(role: "pipeline_advancer")

    change_column_null :ductwork_executions, :crash_count, false
  end

  def down
    remove_column :ductwork_processes, :role, :string
  end
end
