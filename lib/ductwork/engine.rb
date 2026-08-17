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
      Ductwork.logger ||= Ductwork::Configuration::DEFAULT_LOGGER
    end
  end
end
