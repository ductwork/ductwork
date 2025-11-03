# frozen_string_literal: true

module Ductwork
  class BranchBuilder
    attr_reader :klass

    def initialize(klass:, definition:)
      @klass = klass
      @definition = definition
    end

    # TODO: implement `#chain`, `#divide`, `#expand`, and `#collapse`

    def combine(*branch_builders, into:)
      definition[:edges][klass.name] << {
        to: [into.name],
        type: :combine,
      }
      branch_builders.each do |branch|
        definition[:edges][branch.klass.name] << {
          to: [into.name],
          type: :combine,
        }
      end
      definition[:nodes].push(into.name)
      definition[:edges][into.name] = []
    end

    private

    attr_reader :definition
  end
end
