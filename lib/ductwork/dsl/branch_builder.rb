# frozen_string_literal: true

module Ductwork
  module DSL
    class BranchBuilder
      class CollapseError < StandardError; end

      attr_reader :last_node

      def initialize(last_node:, definition:)
        @last_node = last_node
        @definition = definition
        @expansions = 0
      end

      def chain(next_klass)
        next_klass_name = node_name(next_klass)
        definition[:edges][last_node][:to] = [next_klass_name]
        definition[:edges][last_node][:type] = :chain
        definition[:nodes].push(next_klass_name)
        definition[:edges][next_klass_name] ||= { klass: next_klass.name }
        @last_node = next_klass_name

        self
      end

      def divide(to:)
        next_nodes = to.map do |klass|
          node = node_name(klass)
          definition[:edges][node] ||= { klass: klass.name }
          node
        end
        definition[:edges][last_node][:to] = next_nodes
        definition[:edges][last_node][:type] = :divide
        definition[:nodes].push(*next_nodes)

        sub_branches = next_nodes.map do |last_node|
          Ductwork::DSL::BranchBuilder.new(last_node:, definition:)
        end

        yield sub_branches

        self
      end

      def combine(*branch_builders, into:)
        next_klass_name = node_name(into)
        definition[:edges][last_node][:to] = [next_klass_name]
        definition[:edges][last_node][:type] = :combine

        branch_builders.each do |branch|
          definition[:edges][branch.last_node][:to] = [next_klass_name]
          definition[:edges][branch.last_node][:type] = :combine
        end
        definition[:nodes].push(next_klass_name)
        definition[:edges][next_klass_name] ||= { klass: into.name }

        self
      end

      def expand(to:)
        next_klass_name = node_name(to)
        definition[:edges][last_node][:to] = [next_klass_name]
        definition[:edges][last_node][:type] = :expand
        definition[:nodes].push(next_klass_name)
        definition[:edges][next_klass_name] ||= { klass: to.name }
        @last_node = next_klass_name
        @expansions += 1

        self
      end

      def collapse(into:)
        if expansions.zero?
          raise CollapseError,
                "Must expand pipeline definition before collapsing steps"
        end

        next_klass_name = node_name(into)
        definition[:edges][last_node][:to] = [next_klass_name]
        definition[:edges][last_node][:type] = :collapse

        definition[:nodes].push(next_klass_name)
        definition[:edges][next_klass_name] ||= { klass: into.name }
        @last_node = next_klass_name
        @expansions -= 1

        self
      end

      private

      attr_reader :definition, :expansions

      def node_name(klass)
        "#{klass.name}.#{SecureRandom.hex(4)}"
      end
    end
  end
end
