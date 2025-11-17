# frozen_string_literal: true

module Ductwork
  module DSL
    class DefinitionBuilder
      class StartError < StandardError; end
      class CollapseError < StandardError; end
      class CombineError < StandardError; end

      def initialize
        @definition = {
          nodes: [],
          edges: {},
        }
        @divisions = 0
        @expansions = 0
        @last_nodes = []
      end

      def start(klass)
        validate_classes!(klass)
        validate_start_once!
        add_new_nodes(klass)

        self
      end

      # NOTE: there is a bug here that does not allow the user to reuse step
      # classes in the same pipeline. i'll fix this later
      def chain(klass)
        validate_classes!(klass)
        validate_definition_started!(action: "chaining")
        add_edge_to_last_nodes(klass, type: :chain)
        add_new_nodes(klass)

        self
      end

      def divide(to:)
        validate_classes!(to)
        validate_definition_started!(action: "dividing chain")
        add_edge_to_last_nodes(*to, type: :divide)
        add_new_nodes(*to)

        @divisions += 1

        if block_given?
          branches = to.map do |klass|
            Ductwork::DSL::BranchBuilder
              .new(klass:, definition:)
          end

          yield branches
        end

        self
      end

      def combine(into:)
        validate_classes!(into)
        validate_definition_started!(action: "combining steps")
        validate_definition_divided!

        @divisions -= 1

        last_nodes = definition[:nodes].reverse.select do |node|
          definition[:edges][node].empty?
        end
        last_nodes.each do |node|
          definition[:edges][node] << {
            to: [into.name],
            type: :combine,
          }
        end
        add_new_nodes(into)

        self
      end

      def expand(to:)
        validate_classes!(to)
        validate_definition_started!(action: "expanding chain")
        add_edge_to_last_nodes(to, type: :expand)
        add_new_nodes(to)

        @expansions += 1

        self
      end

      def collapse(into:)
        validate_classes!(into)
        validate_definition_started!(action: "collapsing steps")
        validate_definition_expanded!
        add_edge_to_last_nodes(into, type: :collapse)
        add_new_nodes(into)

        @expansions -= 1

        self
      end

      def on_halt(klass)
        validate_classes!(klass)

        definition[:metadata] ||= {}
        definition[:metadata][:on_halt] = {}
        definition[:metadata][:on_halt][:klass] = klass.name

        self
      end

      def complete
        validate_definition_started!(action: "completing")

        definition
      end

      private

      attr_reader :definition, :divisions, :expansions, :last_nodes

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

      def validate_definition_divided!
        if divisions.zero?
          raise CombineError, "Must divide pipeline definition before combining steps"
        end
      end

      def validate_definition_expanded!
        if expansions.zero?
          raise CollapseError, "Must expand pipeline definition before collapsing steps"
        end
      end

      def add_new_nodes(*klasses)
        nodes = klasses.map(&:name)
        @last_nodes = Array(nodes)

        definition[:nodes].push(*nodes)
        klasses.each do |klass|
          definition[:edges][klass.name] ||= []
        end
      end

      def add_edge_to_last_nodes(*klasses, type:)
        last_nodes.each do |last_node|
          definition[:edges][last_node] << {
            to: klasses.map(&:name),
            type: type,
          }
        end
      end
    end
  end
end
