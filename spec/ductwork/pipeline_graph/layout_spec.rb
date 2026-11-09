# frozen_string_literal: true

RSpec.describe Ductwork::PipelineGraph::Layout do
  def layout(nodes, links)
    described_class.new(nodes: nodes, links: links, card_height: 100)
  end

  def column_of(graph, node)
    pitch = described_class::CARD_WIDTH + described_class::COLUMN_GAP

    (graph.position(node).first - described_class::PADDING) / pitch
  end

  it "lays a chain out in one row" do
    graph = layout(%w[a b c], [%w[a b], %w[b c]])

    expect([column_of(graph, "a"), column_of(graph, "b"), column_of(graph, "c")]).to eq([0, 1, 2])
    expect(%w[a b c].map { |node| graph.position(node).last }.uniq.length).to eq(1)
  end

  it "centers a split and its merge around the branches" do
    graph = layout(%w[a b c d], [%w[a b], %w[a c], %w[b d], %w[c d]])
    b_y = graph.position("b").last
    c_y = graph.position("c").last

    expect(c_y - b_y).to be >= 100 + described_class::ROW_GAP
    expect(graph.position("a").last).to be_within(1).of((b_y + c_y) / 2.0)
    expect(graph.position("d").last).to be_within(1).of((b_y + c_y) / 2.0)
  end

  it "places a merge after its longest branch" do
    graph = layout(%w[a b c e d], [%w[a b], %w[a c], %w[b d], %w[c e], %w[e d]])

    expect(column_of(graph, "d")).to eq(3)
  end

  it "routes a link past the columns it spans, clear of their cards" do
    graph = layout(%w[a b c e d], [%w[a b], %w[a c], %w[b d], %w[c e], %w[e d]])

    route = graph.route("b", "d")

    expect(route.scan("C").length).to eq(2)
    expect(graph.position("e").last - graph.position("b").last).to be >= 124
  end

  it "keeps every card inside the canvas without overlaps" do
    nodes = %w[a b c d e f g h]
    links = [%w[a b], %w[a c], %w[a d], %w[b e], %w[b f], %w[e g], %w[f g], %w[g h], %w[c h], %w[d h]]
    graph = layout(nodes, links)
    positions = nodes.map { |node| graph.position(node) }

    expect(positions.uniq.length).to eq(nodes.length)
    positions.group_by(&:first).each_value do |column|
      column.map(&:last).sort.each_cons(2) { |top, bottom| expect(bottom - top).to be >= 124 }
    end
    expect(positions.map(&:last).min).to be >= 0
    expect(positions.map(&:last).max + 100).to be <= graph.height
    expect(positions.map(&:first).max + described_class::CARD_WIDTH).to be <= graph.width
  end

  it "does not hang on a definition with a backward link" do
    graph = layout(%w[a b], [%w[a b], %w[b a]])

    expect(graph.route("b", "a")).to start_with("M")
  end
end
