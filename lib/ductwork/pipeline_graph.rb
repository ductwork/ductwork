# frozen_string_literal: true

module Ductwork
  # A run's definition drawn as a graph, with each node summarizing the steps
  # created for it so far. Aggregating by node keeps the drawing the same size
  # however far a pipeline fans out.
  class PipelineGraph # rubocop:todo Metrics/ClassLength
    STATUS_ORDER = %w[failed in_progress waiting advancing pending completed].freeze
    BAR_INSET = 12
    BAR_TOP = 50
    BAR_HEIGHT = 6
    BAR_MINIMUM_SEGMENT = 3
    HEADER_HEIGHT = 46
    LABELS_TOP = 62
    LABEL_ROW_HEIGHT = 18
    LABEL_COLUMNS = 2
    CARD_BOTTOM_PADDING = 8

    Node = Struct.new(:id, :klass, :transition, :state, :x, :y, :segments, :labels) do
      def name
        klass.demodulize
      end
    end
    Edge = Struct.new(:path, :state)
    Segment = Struct.new(:status, :x, :width)
    Label = Struct.new(:text, :tone, :status, :wide)

    def initialize(run)
      @run = run
      @definition = run.parsed_definition
    end

    def present?
      node_ids.any?
    end

    def nodes
      @nodes ||= node_ids.map { |id| build_node(id) }
    end

    def edges
      @edges ||= links.map do |from, to|
        Edge.new(layout.route(from, to), edge_state(to))
      end
    end

    delegate :width, :height, to: :layout

    def card_width
      Layout::CARD_WIDTH
    end

    def card_height
      LABELS_TOP + (label_rows * LABEL_ROW_HEIGHT) + CARD_BOTTOM_PADDING
    end

    def bar_width
      card_width - (BAR_INSET * 2)
    end

    private

    attr_reader :run, :definition

    def layout
      @layout ||= Layout.new(nodes: node_ids, links: links, card_height: card_height)
    end

    def node_ids
      @node_ids ||= Array(definition[:nodes]).uniq
    end

    def links
      @links ||= node_ids.flat_map do |from|
        successors(from).keys.map { |to| [from, to] }
      end.uniq
    end

    # NOTE: a `divert` keeps its successors as a `{ key => node }` map and every
    # other transition as a list, so this returns `{ node => key }` for both.
    def successors(from)
      to = definition.dig(:edges, from, :to)
      keys = to.is_a?(Hash) ? to.invert : Array(to).index_with(nil)

      keys.slice(*node_ids)
    end

    def build_node(id)
      x, y = layout.position(id)

      Node.new(
        id,
        definition.dig(:edges, id, :klass).to_s,
        transitions.fetch(id, "start"),
        node_state(id),
        x,
        y,
        segments(id),
        labels(id)
      )
    end

    def transitions
      @transitions ||= node_ids.each_with_object({}) do |from, result|
        type = definition.dig(:edges, from, :type)

        successors(from).each do |to, key|
          result[to] = [".#{type}", key].compact.join(" ")
        end
      end
    end

    def node_state(id)
      statuses = status_counts(id).keys

      if halts.key?(id) || statuses.include?("failed")
        "failed"
      elsif statuses.any?
        statuses == ["completed"] ? "completed" : "active"
      else
        run.completed? ? "skipped" : "pending"
      end
    end

    def edge_state(to)
      status_counts(to).any? ? "reached" : node_state(to)
    end

    def status_counts(id)
      step_counts.fetch(id, {})
    end

    def step_counts
      @step_counts ||= run.steps.group(:node, :status).count.each_with_object({}) do |((node, status), count), result|
        (result[node] ||= {})[status] = count
      end
    end

    def ordered_status_counts(id)
      status_counts(id).sort_by { |status, _count| STATUS_ORDER.index(status) || STATUS_ORDER.length }
    end

    def segments(id)
      counts = ordered_status_counts(id)
      total = counts.sum { |_status, count| count }.to_f
      sizes = counts.map { |_status, count| [(count / total) * bar_width, BAR_MINIMUM_SEGMENT].max }
      scale = bar_width / sizes.sum.to_f
      offset = BAR_INSET

      counts.zip(sizes).map do |(status, _count), size|
        width = (size * scale).round(2)

        Segment.new(status, offset.round(2), width).tap { offset += width }
      end
    end

    def labels(id)
      labels = halt_labels(id) + status_labels(id) + execution_labels(id)

      labels.empty? ? [empty_label] : labels
    end

    def halt_labels(id)
      halts.fetch(id, {}).map do |reason, count|
        Label.new([count, "halted:", reason&.humanize&.downcase].compact.join(" "), "failed", nil, true)
      end
    end

    def status_labels(id)
      ordered_status_counts(id).map do |status, count|
        Label.new("#{count} #{status.tr("_", "-")}", status, status, false)
      end
    end

    def execution_labels(id)
      [
        (Label.new("#{retried[id]} retried", "warning", nil, false) if retried.key?(id)),
        (Label.new("#{crash_recovered[id]} crash-recovered", "warning", nil, true) if crash_recovered.key?(id)),
      ].compact
    end

    def empty_label
      text = if run.completed?
               "not taken"
             elsif run.halted?
               "not reached"
             else
               "no steps yet"
             end

      Label.new(text, "quiet", nil, false)
    end

    def label_rows
      @label_rows ||= node_ids.map do |id|
        (labels(id).sum { |label| label.wide ? LABEL_COLUMNS : 1 } / LABEL_COLUMNS.to_f).ceil
      end.max || 1
    end

    def retried
      @retried ||= steps_with_execution_where("ductwork_executions.retry_count > 0")
    end

    def crash_recovered
      @crash_recovered ||= steps_with_execution_where("ductwork_executions.crash_count > 0")
    end

    def steps_with_execution_where(condition)
      run
        .steps
        .joins(job: :executions)
        .where(condition)
        .group("ductwork_steps.node")
        .distinct
        .count("ductwork_steps.id")
    end

    # A halted branch stops at its latest step, which is the node to blame.
    def halts
      @halts ||= begin
        reasons = run.branches.halted.pluck(:id, :halt_reason).to_h
        latest_nodes = run.steps.where(branch_id: reasons.keys).order(:started_at, :id).pluck(:branch_id, :node).to_h

        latest_nodes.each_with_object({}) do |(branch_id, node), result|
          counts = (result[node] ||= Hash.new(0))
          counts[reasons[branch_id]] += 1
        end
      end
    end
  end
end
