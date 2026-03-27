# frozen_string_literal: true

require "rails/generators/migration"
require "rails/generators/active_record/migration"

module Ductwork
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def create_files
      template "config/ductwork.yml"
      template "bin/ductwork"

      chmod "bin/ductwork", 0o755 & ~File.umask, verbose: false

      migration_template "db/create_ductwork_pipelines.rb",
                         "db/migrate/create_ductwork_pipelines.rb"
      migration_template "db/create_ductwork_branches.rb",
                         "db/migrate/create_ductwork_branches.rb"
      migration_template "db/create_ductwork_branch_links.rb",
                         "db/migrate/create_ductwork_branch_links.rb"
      migration_template "db/create_ductwork_steps.rb",
                         "db/migrate/create_ductwork_steps.rb"
      migration_template "db/create_ductwork_jobs.rb",
                         "db/migrate/create_ductwork_jobs.rb"
      migration_template "db/create_ductwork_processes.rb",
                         "db/migrate/create_ductwork_processes.rb"
      migration_template "db/create_ductwork_executions.rb",
                         "db/migrate/create_ductwork_executions.rb"
      migration_template "db/create_ductwork_availabilities.rb",
                         "db/migrate/create_ductwork_availabilities.rb"
      migration_template "db/create_ductwork_runs.rb",
                         "db/migrate/create_ductwork_runs.rb"
      migration_template "db/create_ductwork_results.rb",
                         "db/migrate/create_ductwork_results.rb"
      migration_template "db/create_ductwork_transitions.rb",
                         "db/migrate/create_ductwork_transitions.rb"
      migration_template "db/create_ductwork_advancements.rb",
                         "db/migrate/create_ductwork_advancements.rb"
      migration_template "db/create_ductwork_tuples.rb",
                         "db/migrate/create_ductwork_tuples.rb"

      route <<~ROUTE
        # This mounts the web dashboard. It is recommended to add authentication around it.
        mount Ductwork::Engine, at: "/ductwork"
      ROUTE
    end
  end
end
