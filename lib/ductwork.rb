# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/hash"

require_relative "ductwork/configuration"
require_relative "ductwork/definition"
require_relative "ductwork/definition_builder"
require_relative "ductwork/pipeline"
require_relative "ductwork/supervisor"
require_relative "ductwork/version"

module Ductwork
  def self.pipelines
    @_pipelines ||= []
  end

  # NOTE: this is test interface only
  def self.reset!
    @_pipelines = nil
  end
end
