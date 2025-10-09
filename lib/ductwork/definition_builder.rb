# frozen_string_literal: true

module Ductwork
  class DefinitionBuilder
    class StartError < StandardError; end
    class CollapseError < StandardError; end
    class CombineError < StandardError; end

    def initialize
      @definition = Ductwork::Definition.new
      @started = false
      @branch_count = 0
      @depth = []
    end

    def start(klass)
      if started?
        raise StartError, "Can only start pipeline once"
      end

      @started = true
      @branch_count += 1
      definition.add_starting_node(klass)
      self
    end

    def chain(klass)
      if not_started?
        raise StartError, "Must start pipeline before chaining"
      end

      definition.add_node(klass, transition: :chain)
      self
    end

    def divide(to:)
      if not_started?
        raise StartError, "Must start pipeline before dividing"
      end

      @branch_count += 1
      definition.add_nodes(to, transition: :divide)
      self
    end

    def combine(into:)
      if not_started?
        raise StartError, "Must start pipeline before combining"
      end

      if not_divided?
        raise CombineError, "Must divide pipeline before combining steps"
      end

      # create edges to single node from all current stage nodes
      definition.combine(into)

      self
    end

    ##############################
    ## OLD
    ##############################
    def expand(to: klass)
      if not_started?
        raise StartError, "Must start pipeline before expanding chain"
      end

      depth << 1
      add_step(klass: to, type: :expand)
      self
    end

    def collapse(into: klass)
      if not_started?
        raise StartError, "Must start pipeline before collapsing steps"
      end

      if depth.pop.nil?
        raise CollapseError, "Must expand pipeline before collapsing steps"
      end

      add_step(klass: into, type: :collapse)
      self
    end

    def complete
      if not_started?
        raise StartError, "Must start pipeline before completing definition"
      end

      definition
    end

    private

    attr_reader :definition, :started, :depth, :branch_count

    def started?
      @started
    end

    def not_started?
      !started?
    end

    def not_divided?
      branch_count == 1
    end

    def add_step(klass:, type:)
      step = StepDefinition.new(klass: klass.name.to_s, type: type)
      definition.steps << step
    end
  end
end
