# frozen_string_literal: true

require "active_record"
require "active_support"
require "logger"
require "rails/engine"
require "securerandom"
require "zeitwerk"

require "ductwork/engine"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("cli" => "CLI")
loader.inflector.inflect("dsl" => "DSL")
loader.ignore("#{__dir__}/generators")
loader.ignore("#{__dir__}/ductwork/testing")
loader.ignore("#{__dir__}/ductwork/testing.rb")
loader.setup

module Ductwork
  class << self
    attr_accessor :app_executor, :configuration, :logger
    attr_writer :defined_pipelines, :hooks

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

    private

    def add_lifecycle_hook(target, event, block)
      hooks[target] ||= {}
      hooks[target][event] ||= []
      hooks[target][event].push(block)
    end
  end
end
