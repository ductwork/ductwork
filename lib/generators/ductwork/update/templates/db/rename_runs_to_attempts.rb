# frozen_string_literal: true

class RenameRunsToAttempts < Ductwork::Migration
  def change
    rename_table :ductwork_runs, :ductwork_attempts
  end
end
