# frozen_string_literal: true

module Ductwork
  class BranchBuilder
    attr_reader :last_node

    def initialize(klass:, definition:)
      @last_node = klass.name
      @definition = definition
    end

    # TODO: implement `#expand` and `#collapse`

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

    private

    attr_reader :definition
  end
end
