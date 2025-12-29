# frozen_string_literal: true

module Ductwork
  class Engine < ::Rails::Engine
    isolate_namespace Ductwork

    initializer "ductwork.app_executor", before: :run_prepare_callbacks do |app|
      Ductwork.app_executor = app.executor
    end

    initializer "ductwork.assets.precompile" do |app|
      if app.config.respond_to?(:assets)
        app.config.assets.precompile += %w[
          ductwork/vendor/pico.min.css
          ductwork/vendor/flexboxgrid.min.css
          ductwork/application.css
          ductwork/application.js
        ]
      end
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
        step_directory = Rails.root.join("app/steps")
        pipeline_directory = Rails.root.join("app/pipelines")

        if step_directory.exist?
          loader.eager_load_dir(step_directory)
        end

        if pipeline_directory.exist?
          loader.eager_load_dir(pipeline_directory)
        end
      end
    end
  end
end
