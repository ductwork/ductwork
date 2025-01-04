# frozen_string_literal: true

module Ductwork
  class StepDefinition
    attr_reader :klass, :type

    def initialize(klass:, type:)
      @klass = klass
      @type = type
    end
  end
end
