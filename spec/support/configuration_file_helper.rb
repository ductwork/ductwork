# frozen_string_literal: true

require "fileutils"

module ConfigurationFileHelper
  RSpec.configure do |config|
    config.after do
      if defined?(config_file)
        config_file.close
        config_file.unlink
      end
    end
  end

  def create_temp_file
    Tempfile.new("ductwork.yml").tap do |file|
      file.write(data)
      file.rewind
    end
  end

  def create_default_config_file
    # NOTE: this is kinda terrible as we're double-purpose-ing the `config`
    # directory. it's used for the routes and now it's also used for test files
    File.new("config/ductwork.yml", "w").tap do |file|
      file.write(data)
      file.rewind
    end
  end
end
