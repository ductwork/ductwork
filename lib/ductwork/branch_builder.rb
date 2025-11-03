# frozen_string_literal: true

module Ductwork
  class BranchBuilder
    class CollapseError < StandardError; end

    attr_reader :last_node

    def initialize(klass:, definition:)
      @last_node = klass.name
      @definition = definition
      @expansions = 0
    end

    def chain(next_klass)
      definition[:edges][last_node] << {
        to: [next_klass.name],
        type: :chain,
      }

      definition[:nodes].push(next_klass.name)
      definition[:edges][next_klass.name] = []
      @last_node = next_klass.name

      self
    end

    def divide(to:)
      definition[:edges][last_node] << {
        to: to.map(&:name),
        type: :divide,
      }

      definition[:nodes].push(*to.map(&:name))
      sub_branches = to.map do |klass|
        definition[:edges][klass.name] = []

        Ductwork::BranchBuilder.new(klass: klass, definition: definition)
      end

      yield sub_branches

      self
    end

    def combine(*branch_builders, into:)
      definition[:edges][last_node] << {
        to: [into.name],
        type: :combine,
      }
      branch_builders.each do |branch|
        definition[:edges][branch.last_node] << {
          to: [into.name],
          type: :combine,
        }
      end
      definition[:nodes].push(into.name)
      definition[:edges][into.name] = []

      self
    end

    def expand(to:)
      definition[:edges][last_node] << {
        to: [to.name],
        type: :expand,
      }

      definition[:nodes].push(to.name)
      definition[:edges][to.name] = []
      @last_node = to.name
      @expansions += 1

      self
    end

    def collapse(into:)
      if expansions.zero?
        raise CollapseError,
              "Must expand pipeline definition before collapsing steps"
      end

      definition[:edges][last_node] << {
        to: [into.name],
        type: :collapse,
      }

      definition[:nodes].push(into.name)
      definition[:edges][into.name] = []
      @last_node = into.name
      @expansions -= 1

      self
    end

    private

    attr_reader :definition, :expansions
  end
end
