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
    end
  end
end
