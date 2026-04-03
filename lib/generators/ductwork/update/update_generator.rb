# frozen_string_literal: true

require "rails/generators/migration"
require "rails/generators/active_record/migration"

module Ductwork
  class UpdateGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def create_files
      if Ductwork::Availability.column_names.exclude?("pipeline_klass")
        migration_template "db/denormalize_pipeline_klass_on_availabilities.rb",
                           "db/migrate/denormalize_pipeline_klass_on_availabilities.rb"
      end

      if Ductwork::Pipeline.column_for_attribute("id").type != :uuid
        migration_template "db/migrate_tables_to_uuid_primary_key.rb",
                           "db/migrate/migrate_tables_to_uuid_primary_key.rb"
      end

      if !Ductwork::Record.connection.table_exists?(:ductwork_branches)
        migration_template "db/create_ductwork_branches.rb",
                           "db/migrate/create_ductwork_branches.rb"
      end

      if !Ductwork::Record.connection.table_exists?(:ductwork_branch_links)
        migration_template "db/create_ductwork_branch_links.rb",
                           "db/migrate/create_ductwork_branch_links.rb"
      end

      if Ductwork::Step.column_names.exclude?("branch_id")
        migration_template "db/associate_steps_to_branches.rb",
                           "db/migrate/associate_steps_to_branches.rb"
        migration_template "db/backfill_branch_ids_on_steps.rb",
                           "db/migrate/backfill_branch_ids_on_steps.rb"
      end

      if !Ductwork::Record.connection.table_exists?(:ductwork_transitions)
        migration_template "db/create_ductwork_transitions.rb",
                           "db/migrate/create_ductwork_transitions.rb"
      end

      if !Ductwork::Record.connection.table_exists?(:ductwork_advancements)
        migration_template "db/create_ductwork_advancements.rb",
                           "db/migrate/create_ductwork_advancements.rb"
      end

      if Ductwork::Execution.column_names.include?("process_id")
        migration_template "db/update_process_associations.rb",
                           "db/migrate/update_process_associations.rb"
      end

      if Ductwork::Record.connection.table_exists?(:ductwork_runs)
        migration_template "db/rename_runs_to_attempts.rb",
                           "db/migrate/rename_runs_to_attempts.rb"
      end

      if !Ductwork::Record.connection.table_exists?(:ductwork_runs)
        migration_template "db/create_ductwork_runs.rb",
                           "db/migrate/create_ductwork_runs.rb"
      end

      if Ductwork::Branch.column_names.include?("pipeline_id")
        migration_template "db/associate_branches_to_runs.rb",
                           "db/migrate/associate_branches_to_runs.rb"
      end

      if Ductwork::Step.column_names.include?("pipeline_id")
        migration_template "db/associate_steps_to_runs.rb",
                           "db/migrate/associate_steps_to_runs.rb"
      end

      if Ductwork::Tuple.column_names.include?("pipeline_id")
        migration_template "db/associate_tuples_to_runs.rb",
                           "db/migrate/associate_tuples_to_runs.rb"
      end
    end
  end
end
