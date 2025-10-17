# frozen_string_literal: true

module Ductwork
  class Branch
    attr_reader :steps, :parents, :children

    def initialize(parents: [])
      @steps = []
      @parents = parents
      @children = []
    end

    def start(klass)
      add_step(klass, :start)
    end

    def chain(klass)
      add_step(klass, :chain)
    end

    def divide(to:)
      branches = to.map do |klass|
        self.class.new(parents: [self]).tap do |branch|
          step = Ductwork::PlaceholderStep.new(klass, :divide)

          branch.steps.push(step)
          children.push(branch)
        end
      end

      yield *branches if block_given?

      branches
    end

    def combine(*branches, into:)
      new_branch = self.class.new(parents: [self, *branches])
      step = Ductwork::PlaceholderStep.new(into, :combine)
      new_branch.steps.push(step)
      children.push(new_branch)
      branches.each { |b| b.children.push(new_branch) }
      new_branch
    end

    def expand(klass)
      add_step(klass, :expand)
    end

    def collapse(klass)
      add_step(klass, :collapse)
    end

    private

    def add_step(klass, type)
      step = Ductwork::PlaceholderStep.new(klass, type)
      steps.push(step)
    end
  end
end
