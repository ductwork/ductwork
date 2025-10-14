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

    def divide(klasses)
      klasses.map do |klass|
        self.class.new(parents: [self]).tap do |branch|
          step = Ductwork::PlaceholderStep.new(klass, :divide)

          branch.steps.push(step)
          # do we "complete" this current branch?
          children.push(branch)
        end
      end
    end

    def combine(branch_builder, into:)
      new_branch = self.class.new(parents: [self, branch_builder])
      step = Ductwork::PlaceholderStep.new(into, :combine)
      new_branch.steps.push(step)
      # do we "complete" these branches?
      children.push(new_branch)
      branch_builder.children.push(new_branch)
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
