# frozen_string_literal: true

module Ductwork
  class DefinitionBuilder
    class StartError < StandardError; end
    class CollapseError < StandardError; end
    class CombineError < StandardError; end

    def initialize
      @definition = {
        nodes: [],
        edges: {},
      }
    end

    def start(klass)
      validate_start_once!
      add_new_nodes(klass)

      self
    end

    # NOTE: there is a bug here that does not allow the user to reuse step classes in the same pipeline. i'll fix this
    def chain(klass)
      validate_definition_started!(action: "chaining")
      add_edge_to_last_node(klass, type: :chain)
      add_new_nodes(klass)

      self
    end

    def divide(to:)
      validate_definition_started!(action: "dividing chain")
      add_edge_to_last_node(*to, type: :divide)
      add_new_nodes(*to)

      if block_given?
        branches = to.map do |klass|
          Ductwork::BranchBuilder
            .new(klass: klass, definition: definition)
        end

        yield branches
      end

      self
    end

    def combine(into:)
      validate_definition_started!(action: "combining steps")
      validate_definition_divided!

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
      validate_definition_started!(action: "expanding chain")
      add_edge_to_last_node(to, type: :expand)
      add_new_nodes(to)

      self
    end

    def collapse(into:)
      validate_definition_started!(action: "collapsing steps")
      validate_definition_expanded!
      add_edge_to_last_node(into, type: :collapse)
      add_new_nodes(into)

      self
    end

    def complete
      validate_definition_started!(action: "completing")

      definition
    end

    private

    attr_reader :definition

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
      if last_edge.nil? || last_edge[:type] != :divide
        raise CombineError, "Must divide pipeline definition before combining steps"
      end
    end

    def validate_definition_expanded!
      if last_edge.nil? || last_edge[:type] != :expand
        raise CollapseError, "Must expand pipeline definition before collapsing steps"
      end
    end

    def last_edge
      last_edge_node = definition[:nodes].reverse.find do |node|
        definition[:edges][node].any?
      end

      definition.dig(:edges, last_edge_node, -1)
    end

    def add_new_nodes(*klasses)
      definition[:nodes].push(*klasses.map(&:name))
      klasses.each do |klass|
        definition[:edges][klass.name] = []
      end
    end

    def add_edge_to_last_node(*klasses, type:)
      last_node = definition.dig(:nodes, -1)

      definition[:edges][last_node] << {
        to: klasses.map(&:name),
        type: type,
      }
    end
  end
end
