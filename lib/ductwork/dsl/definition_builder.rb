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
        @stages = []
      end

      def start(klass)
        validate_classes!(klass)
        validate_start_once!
        add_new_nodes(klass)
        increment_position

        self
      end

      def chain(klass)
        validate_classes!(klass)
        validate_definition_started!(action: "chaining")
        add_edge_to_last_nodes(klass, type: :chain)
        add_new_nodes(klass)
        increment_position

        self
      end

      def divide(to:)
        validate_classes!(to)
        validate_definition_started!(action: "dividing chain")
        add_edge_to_last_nodes(*to, type: :divide)
        add_new_nodes(*to)
        increment_position
        divergences.push(:divide)

        if block_given?
          branches = to.map do |klass|
            Ductwork::DSL::BranchBuilder
              .new(klass:, definition:, stages:)
          end

          yield branches
        end

        self
      end

      def combine(into:)
        validate_classes!(into)
        validate_definition_started!(action: "combining steps")
        validate_can_combine!

        divergences.pop

        last_nodes = definition[:nodes].reverse.select do |node|
          definition.dig(:edges, node, :to).blank?
        end
        last_nodes.each do |node|
          definition[:edges][node][:to] = ["#{into.name}.#{stages.length}"]
          definition[:edges][node][:type] = :combine
        end
        add_new_nodes(into)
        increment_position

        self
      end

      def expand(to:)
        validate_classes!(to)
        validate_definition_started!(action: "expanding chain")
        add_edge_to_last_nodes(to, type: :expand)
        add_new_nodes(to)
        increment_position
        divergences.push(:expand)

        self
      end

      def collapse(into:)
        validate_classes!(into)
        validate_definition_started!(action: "collapsing steps")
        validate_can_collapse!
        add_edge_to_last_nodes(into, type: :collapse)
        add_new_nodes(into)
        increment_position
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

      attr_reader :definition, :last_nodes, :divergences, :stages

      def validate_classes!(klasses)
        valid = Array(klasses).all? do |klass|
          klass.is_a?(Class) &&
            klass.method_defined?(:execute) &&
            klass.instance_method(:execute).arity.zero?
        end

        if !valid
          word = if Array(klasses).length > 1
                   "Arguments"
                 else
                   "Argument"
                 end

          raise ArgumentError, "#{word} must be a valid step class"
        end
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
        if divergences.empty?
          raise CombineError, "Must divide pipeline definition before combining steps"
        elsif divergences[-1] != :divide
          raise CombineError, "Ambiguous combine on most recently expanded definition"
        end
      end

      def validate_can_collapse!
        if divergences.empty?
          raise CollapseError, "Must expand pipeline definition before collapsing steps"
        elsif divergences[-1] != :expand
          raise CollapseError, "Ambiguous collapse on most recently divided definition"
        end
      end

      def add_new_nodes(*klasses)
        nodes = klasses.map { |klass| "#{klass.name}.#{stages.length}" }
        @last_nodes = Array(nodes)

        definition[:nodes].push(*nodes)
        klasses.each do |klass|
          node = "#{klass.name}.#{stages.length}"
          definition[:edges][node] ||= { klass: klass.name }
        end
      end

      def add_edge_to_last_nodes(*klasses, type:)
        last_nodes.each do |last_node|
          to = klasses.map { |klass| "#{klass.name}.#{stages.length}" }
          definition[:edges][last_node][:to] = to
          definition[:edges][last_node][:type] = type
        end
      end

      def increment_position
        stages.push(1)
      end
    end
  end
end
