# frozen_string_literal: true

module Ductwork
  module DSL
    class DefinitionBuilder
      class StartError < StandardError; end
      class CollapseError < StandardError; end
      class CombineError < StandardError; end

      def initialize
        @definition = {
          metadata: {},
          nodes: [],
          edges: {},
        }
        @divergences = []
        @last_nodes = []
      end

      def start(klass)
        validate_classes!(klass)
        validate_start_once!

        node = node_name(klass)
        definition[:nodes].push(node)
        definition[:edges][node] = { klass: klass.name }

        @last_nodes = [node]

        self
      end

      def chain(klass)
        validate_classes!(klass)
        validate_definition_started!(action: "chaining")
        add_edge_to_last_nodes(klass, type: :chain)

        self
      end

      def divide(to:) # rubocop:todo Metrics/AbcSize
        validate_classes!(to)
        validate_definition_started!(action: "dividing chain")
        to_nodes = to.map do |to|
          node = node_name(to)
          definition[:edges][node] ||= { klass: to.name }
          node
        end
        last_nodes.each do |last_node|
          definition[:edges][last_node][:to] = to_nodes
          definition[:edges][last_node][:type] = :divide
        end

        @last_nodes = Array(to_nodes)

        definition[:nodes].push(*to_nodes)
        divergences.push(:divide)

        if block_given?
          branches = last_nodes.map do |last_node|
            Ductwork::DSL::BranchBuilder
              .new(last_node:, definition:)
          end

          yield branches
        end

        self
      end

      def combine(into:) # rubocop:todo Metrics/AbcSize
        validate_classes!(into)
        validate_definition_started!(action: "combining steps")
        validate_can_combine!

        divergences.pop

        into_node = node_name(into)
        definition[:edges][into_node] ||= { klass: into.name }
        last_nodes = definition[:nodes].reverse.select do |node|
          definition.dig(:edges, node, :to).blank?
        end
        last_nodes.each do |last_node|
          definition[:edges][last_node][:to] = [into_node]
          definition[:edges][last_node][:type] = :combine
        end

        @last_nodes = Array(into_node)

        definition[:nodes].push(into_node)

        self
      end

      def expand(to:)
        validate_classes!(to)
        validate_definition_started!(action: "expanding chain")
        add_edge_to_last_nodes(to, type: :expand)
        divergences.push(:expand)

        self
      end

      def collapse(into:)
        validate_classes!(into)
        validate_definition_started!(action: "collapsing steps")
        validate_can_collapse!
        add_edge_to_last_nodes(into, type: :collapse)
        divergences.pop

        self
      end

      def on_halt(klass)
        validate_classes!(klass)

        definition[:metadata][:on_halt] = { klass: klass.name }

        self
      end

      def complete
        validate_definition_started!(action: "completing")

        definition
      end

      private

      attr_reader :definition, :last_nodes, :divergences

      def validate_classes!(klasses)
        valid = Array(klasses).all? do |klass|
          klass.is_a?(Class) &&
            klass.method_defined?(:execute) &&
            klass.instance_method(:execute).arity.zero?
        end
        return if valid

        word = Array(klasses).length > 1 ? "Arguments" : "Argument"
        raise ArgumentError, "#{word} must be a valid step class"
      end

      def validate_start_once!
        if definition[:nodes].any?
          raise StartError, "Can only start pipeline definition once"
        end
      end

      def validate_definition_started!(action:)
        if definition[:nodes].empty?
          raise StartError, "Must start pipeline definition before #{action}"
        end
      end

      def validate_can_combine!
        case divergences
        in []
          raise CombineError, "Must divide pipeline definition before combining steps"
        in *_, :divide
          nil
        else
          raise CombineError, "Ambiguous combine on most recently expanded definition"
        end
      end

      def validate_can_collapse!
        case divergences
        in []
          raise CollapseError, "Must expand pipeline definition before collapsing steps"
        in *_, :expand
          nil
        else
          raise CollapseError, "Ambiguous collapse on most recently divided definition"
        end
      end

      def add_edge_to_last_nodes(*klasses, type:)
        to_nodes = klasses.map do |klass|
          node = node_name(klass)
          definition[:edges][node] ||= { klass: klass.name }
          node
        end
        last_nodes.each do |last_node|
          definition[:edges][last_node][:to] = to_nodes
          definition[:edges][last_node][:type] = type
        end

        @last_nodes = Array(to_nodes)

        definition[:nodes].push(*to_nodes)
      end

      def node_name(klass)
        "#{klass.name}.#{SecureRandom.hex(4)}"
      end
    end
  end
end
