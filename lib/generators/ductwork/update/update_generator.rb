# frozen_string_literal: true

require "rails/generators/migration"
require "rails/generators/active_record/migration"

module Ductwork
  class UpdateGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def create_files
      migration_template "db/denormalize_pipeline_klass_on_availabilities.rb",
                         "db/migrate/denormalize_pipeline_klass_on_availabilities.rb"
    end
  end
end
