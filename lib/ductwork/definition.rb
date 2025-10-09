# frozen_string_literal: true

module Ductwork
  class Definition
    attr_reader :stages, :current_stage

    def initialize
      @stages = []
    end

    def add_starting_node(klass)
      stage = Ductwork::StageBuilder.new
      node = Ductwork::Node.new(klass)
      stage.nodes.push(node)
      stages.push(stage)
      @current_stage = stage
    end

    def add_node(klass, transition:)
      stage = Ductwork::StageBuilder.new
      node = Ductwork::Node.new(klass)
      current_stage.nodes.last.add_edge(to: node, type: transition)
      stage.nodes.push(node)
      stages.push(stage)
      @current_stage = stage
    end

    def add_nodes(klasses, transition:)
      stage = Ductwork::StageBuilder.new
      nodes = klasses.map do |klass|
        node = Ductwork::Node.new(klass)
        current_stage.nodes.last.add_edge(to: node, type: transition)
        node
      end
      stage.nodes.concat(nodes)
      stages.push(stage)
      @current_stage = stage
    end

    def combine(into)
      # stuff
    end
  end
end
