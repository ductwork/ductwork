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

      migration_template "db/create_ductwork_pipelines.rb",
                         "db/migrate/create_ductwork_pipelines.rb"
      migration_template "db/create_ductwork_steps.rb",
                         "db/migrate/create_ductwork_steps.rb"
      migration_template "db/create_ductwork_jobs.rb",
                         "db/migrate/create_ductwork_jobs.rb"
      migration_template "db/create_ductwork_executions.rb",
                         "db/migrate/create_ductwork_executions.rb"
      migration_template "db/create_ductwork_availabilities.rb",
                         "db/migrate/create_ductwork_availabilities.rb"
      migration_template "db/create_ductwork_processes.rb",
                         "db/migrate/create_ductwork_processes.rb"

      chmod "bin/ductwork", 0o755 & ~File.umask, verbose: false
    end
  end
end
