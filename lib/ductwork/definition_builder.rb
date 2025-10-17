# frozen_string_literal: true

module Ductwork
  class DefinitionBuilder
    class StartError < StandardError; end
    class CollapseError < StandardError; end
    class CombineError < StandardError; end

    def initialize
      @definition = Ductwork::Definition.new
      @current_branches = []
      @divisions = 0
      @expansions = 0
    end

    def start(klass)
      if started?
        raise StartError, "Can only start pipeline definition once"
      end

      branch = Branch.new
      branch.start(klass)
      definition.branch = branch
      @current_branches = [branch]

      self
    end

    def chain(klass)
      if !started?
        raise StartError, "Must start pipeline definition before chaining"
      end

      current_branches.sole.chain(klass)

      self
    end

    def divide(to:)
      if !started?
        raise StartError, "Must start pipeline definition before dividing"
      end

      branches = current_branches.sole.divide(to:)
      @current_branches = branches
      @divisions += 1

      yield branches if block_given?

      self
    end

    def combine(into:)
      if !started?
        raise StartError, "Must start pipeline definition before combining"
      end

      if divisions.zero?
        raise CombineError, "Must divide pipeline definition before combining steps"
      end

      branch = current_branches[0].combine(*current_branches[1..], into: into)
      @current_branches = [branch]
      @divisions -= 1

      self
    end

    def expand(to:)
      if !started?
        raise StartError, "Must start pipeline definition before expanding chain"
      end

      current_branches.sole.expand(to)
      @expansions += 1

      self
    end

    def collapse(into:)
      if !started?
        raise StartError, "Must start pipeline definition before collapsing steps"
      end

      if expansions.zero?
        raise CollapseError, "Must expand pipeline definition before collapsing steps"
      end

      @expansions -= 1
      current_branches.sole.collapse(into)

      self
    end

    def complete
      if !started?
        raise StartError, "Must start pipeline definition before completing"
      end

      # create Branches and PlaceholderSteps or something

      definition
    end

    private

    attr_reader :definition, :current_branches, :divisions, :expansions

    def started?
      current_branches.any?
    end
  end
end
