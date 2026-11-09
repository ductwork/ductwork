# frozen_string_literal: true

module Ductwork
  class PipelineGraph
    # Places a pipeline's nodes in columns by longest path from the start, so
    # branches of different lengths still line up where they merge. A link
    # that spans several columns is routed through a placeholder in each one
    # so it runs around the cards in between rather than behind them.
    class Layout
      CARD_WIDTH = 208
      COLUMN_GAP = 48
      ROW_GAP = 24
      PADDING = 8
      SWEEPS = 8

      attr_reader :width, :height

      def initialize(nodes:, links:, card_height:)
        @nodes = nodes
        @links = links
        @card_height = card_height
        @pitch = card_height + ROW_GAP

        assign_columns
        subdivide_links
        order_columns
        assign_rows
        measure
      end

      def position(node)
        [x(node), y(node)]
      end

      def route(from, to)
        chain = chains.fetch([from, to])
        start = "M#{right(chain.first).join(" ")}"
        curves = chain.each_cons(2).map { |a, b| curve(a, b) }

        [start, *curves].join(" ")
      end

      private

      attr_reader :nodes, :links, :card_height, :pitch, :column, :columns, :chains, :rows,
                  :predecessors, :successors

      def assign_columns
        @column = nodes.to_h { |node| [node, 0] }
        outgoing = links.group_by(&:first)

        nodes.each do |node|
          outgoing.fetch(node, []).map(&:last).each do |to|
            column[to] = [column[to], column[node] + 1].max
          end
        end
      end

      def subdivide_links
        @predecessors = Hash.new { |hash, key| hash[key] = [] }
        @successors = Hash.new { |hash, key| hash[key] = [] }
        @chains = links.to_h { |from, to| [[from, to], chain_for(from, to)] }

        chains.each_value do |chain|
          chain.each_cons(2) do |a, b|
            successors[a] << b
            predecessors[b] << a
          end
        end
      end

      def chain_for(from, to)
        placeholders = ((column[from] + 1)...column[to]).map do |index|
          [from, to, index].tap { |placeholder| column[placeholder] = index }
        end

        [from, *placeholders, to]
      end

      def order_columns
        @columns = column.keys.group_by { |vertex| column[vertex] }.sort.map(&:last)

        (1...columns.length).each do |index|
          ranks = columns[index - 1].each_with_index.to_h
          columns[index] = columns[index].sort_by.with_index do |vertex, position|
            [mean(predecessors[vertex].filter_map { |predecessor| ranks[predecessor] }) || position, position]
          end
        end
      end

      def assign_rows
        @rows = {}
        columns.each do |vertices|
          vertices.each_with_index { |vertex, index| rows[vertex] = (index - ((vertices.length - 1) / 2.0)) * pitch }
        end

        SWEEPS.times do
          sweep(columns, predecessors)
          sweep(columns.reverse, successors)
        end
        sweep(columns, predecessors)
      end

      def sweep(ordered_columns, neighbors)
        ordered_columns.each do |vertices|
          targets = vertices.map { |vertex| mean(neighbors[vertex].map { |other| rows[other] }) || rows[vertex] }

          vertices.zip(separate(targets)) { |vertex, row| rows[vertex] = row }
        end
      end

      # Pushes rows apart to at least `pitch`, keeping their order and their
      # overall center where the targets asked for it.
      def separate(targets)
        placed = targets.each_with_object([]) do |target, result|
          result << (result.empty? ? target : [target, result.last + pitch].max)
        end
        shift = mean(targets) - mean(placed)

        placed.map { |row| row + shift }
      end

      def measure
        top = rows.values.min || 0
        rows.transform_values! { |row| (row - top).round + PADDING }

        @width = (PADDING * 2) + (columns.length * CARD_WIDTH) + ([columns.length - 1, 0].max * COLUMN_GAP)
        @height = (rows.values.max || 0) + card_height + PADDING
      end

      def x(vertex)
        PADDING + (column[vertex] * (CARD_WIDTH + COLUMN_GAP))
      end

      def y(vertex)
        rows[vertex]
      end

      def left(vertex)
        [x(vertex), y(vertex) + (card_height / 2)]
      end

      def right(vertex)
        [x(vertex) + CARD_WIDTH, y(vertex) + (card_height / 2)]
      end

      def curve(from, to)
        (start_x, start_y) = right(from)
        (end_x, end_y) = left(to)
        middle = (start_x + end_x) / 2
        path = "C#{middle} #{start_y}, #{middle} #{end_y}, #{end_x} #{end_y}"

        nodes.include?(to) ? path : "#{path} L#{right(to).join(" ")}"
      end

      def mean(values)
        values.sum.to_f / values.length if values.any?
      end
    end
  end
end
