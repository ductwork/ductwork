# frozen_string_literal: true

require "debug"
require "bundler"

require "ductwork"

Bundler.require :default, :development

require "rails/generators"

# Simulate using the generator, most importantly to create migration files
Rails::Generators.invoke(
  "ductwork:install",
  ["--force"],
  destination_root: Rails.root.join("spec", "internal").to_s
)
Combustion.initialize! :active_record

require "rspec/rails"

Dir
  .glob("support/**/*.rb", base: "spec")
  .map { |path| path.delete_suffix(".rb") }
  .each { |filename| require filename }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    Ductwork.configuration = Ductwork::Configuration.new
    Ductwork.configuration.logger = ::Logger.new("log/test.log", 10, 1_024_000)
  end

  config.after do
    Ductwork.reset!
  end
end
