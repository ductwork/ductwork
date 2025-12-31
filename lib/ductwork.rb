# frozen_string_literal: true

require "active_record"
require "active_support"
require "action_controller"
require "action_view"
require "logger"
require "rails/engine"
require "securerandom"
require "zeitwerk"

module Ductwork
  class << self
    attr_accessor :app_executor, :configuration, :loader, :logger
    attr_writer :defined_pipelines, :hooks

    def eager_load
      loader.eager_load
    end

    def wrap_with_app_executor(&block)
      if app_executor.present?
        app_executor.wrap(&block)
      else
        yield
      end
    end

    def hooks
      @hooks ||= {
        supervisor: { start: [], stop: [] },
        advancer: { start: [], stop: [] },
        worker: { start: [], stop: [] },
      }
    end

    def on_supervisor_start(&block)
      add_lifecycle_hook(:supervisor, :start, block)
    end

    def on_supervisor_stop(&block)
      add_lifecycle_hook(:supervisor, :stop, block)
    end

    def on_advancer_start(&block)
      add_lifecycle_hook(:advancer, :start, block)
    end

    def on_advancer_stop(&block)
      add_lifecycle_hook(:advancer, :stop, block)
    end

    def on_worker_start(&block)
      add_lifecycle_hook(:worker, :start, block)
    end

    def on_worker_stop(&block)
      add_lifecycle_hook(:worker, :stop, block)
    end

    def defined_pipelines
      @defined_pipelines ||= []
    end

    def validate!
      step_directory = Rails.root.join("app/steps")
      pipeline_directory = Rails.root.join("app/pipelines")
      loader = if defined?(Rails.autoloaders)
                 Rails.autoloaders.main
               else
                 Ductwork.loader
               end

      if step_directory.exist?
        loader.eager_load_dir(step_directory)
      end

      if pipeline_directory.exist?
        loader.eager_load_dir(pipeline_directory)
      end

      true
    end

    private

    def add_lifecycle_hook(target, event, block)
      hooks[target] ||= {}
      hooks[target][event] ||= []
      hooks[target][event].push(block)
    end
  end
end

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("cli" => "CLI")
loader.inflector.inflect("dsl" => "DSL")
loader.inflector.inflect("rspec" => "RSpec")
loader.collapse("#{__dir__}/ductwork/models")
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/ductwork/testing")
loader.ignore("#{__dir__}/ductwork/testing.rb")
loader.setup

Ductwork.loader = loader

require "ductwork/engine"
