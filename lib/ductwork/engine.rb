# frozen_string_literal: true

module Ductwork
  class Engine < ::Rails::Engine
    isolate_namespace Ductwork

    initializer "ductwork.app_executor", before: :run_prepare_callbacks do |app|
      Ductwork.app_executor = app.executor
    end

    initializer "ductwork.configure" do
      Ductwork.configuration ||= Ductwork::Configuration.new
      Ductwork.logger ||= Ductwork::Configuration::DEFAULT_LOGGER
    end

    initializer "ductwork.validate_definitions", after: :load_config_initializers do
      config.after_initialize do
        # Load steps and pipelines so definition validation runs and bugs
        # can be caught simply by booting the app or running tests
        loader = Rails.autoloaders.main
        loader.eager_load_dir(Rails.root.join("app/steps"))
        loader.eager_load_dir(Rails.root.join("app/pipelines"))
      end
    end
  end
end
