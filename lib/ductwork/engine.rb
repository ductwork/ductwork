# frozen_string_literal: true

module Ductwork
  class Engine < ::Rails::Engine
    initializer "ductwork.app_executor", before: :run_prepare_callbacks do |app|
      Ductwork.app_executor = app.executor
    end

    initializer "ductwork.configure" do
      Ductwork.configuration ||= Ductwork::Configuration.new
      Ductwork.configuration.logger = Rails.logger
    end
  end
end
