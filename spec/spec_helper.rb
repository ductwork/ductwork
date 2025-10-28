# frozen_string_literal: true

require "debug"
require "bundler"

require "ductwork"

Bundler.require :default, :development
Combustion.initialize! :active_record

require "rspec/rails"
require "sidekiq/testing"

Dir
  .glob("support/**/*.rb", base: "spec")
  .map { |file| file.delete_suffix(".rb") }
  .each { |file| require file }

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
    Ductwork.reset!
  end
end
