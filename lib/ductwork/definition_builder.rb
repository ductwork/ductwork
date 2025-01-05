# frozen_string_literal: true

module Ductwork
  class DefinitionBuilder
    class StartError < StandardError; end
    class CollapseError < StandardError; end

    def initialize
      @definition = Ductwork::Definition.new
      @started = false
      @depth = []
    end

    def start(klass)
      if started
        raise StartError, "Can only start pipeline once"
      end

      @started = true
      add_step(klass: klass, type: :start)
      self
    end

    def chain(klass)
      if !started
        raise StartError, "Must start pipeline before chaining"
      end

      add_step(klass: klass, type: :chain)
      self
    end

    def expand_chain(klass)
      if !started
        raise StartError, "Must start pipeline before expanding chain"
      end

      depth << 1
      add_step(klass: klass, type: :expand)
      self
    end

    def collapse_chain(klass)
      if !started
        raise StartError, "Must start pipeline before collapsing chain"
      end

      if depth.pop.nil?
        raise CollapseError, "Must expand pipeline before collapsing chain"
      end

      add_step(klass: klass, type: :collapse)
      self
    end

    def complete
      if !started
        raise StartError, "Must start pipeline before completing definition"
      end

      definition
    end

    private

    attr_reader :definition, :started, :depth

    def add_step(klass:, type:)
      step = StepDefinition.new(klass: klass.name.to_s, type: type)
      definition.steps << step
    end
  end
end
