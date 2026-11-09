# frozen_string_literal: true

RSpec.describe Ductwork::PipelineGraph do
  let(:definition) do
    {
      nodes: %w[Start.a Ns::Work.b Good.c Bad.d Done.e],
      edges: {
        "Start.a" => { klass: "Start", to: ["Ns::Work.b"], type: "expand" },
        "Ns::Work.b" => { klass: "Ns::Work", to: { success: "Good.c", otherwise: "Bad.d" }, type: "divert" },
        "Good.c" => { klass: "Good", to: ["Done.e"], type: "converge" },
        "Bad.d" => { klass: "Bad", to: ["Done.e"], type: "converge" },
        "Done.e" => { klass: "Done" },
      },
    }
  end
  let(:status) { "in_progress" }
  let(:run) { create(:run, definition: definition.to_json, status: status) }

  def node(id, graph = described_class.new(run))
    graph.nodes.find { |candidate| candidate.id == id }
  end

  def label_texts(id)
    node(id).labels.map(&:text)
  end

  def step_at(node, **attributes)
    create(:step, run: run, node: node, klass: node.split(".").first, **attributes)
  end

  it "has nothing to draw without a definition" do
    expect(described_class.new(create(:run))).not_to be_present
  end

  it "builds a node per definition node and an edge per link" do
    graph = described_class.new(run)

    expect(graph.nodes.map(&:id)).to eq(definition[:nodes])
    expect(graph.edges.length).to eq(5)
  end

  it "names the transition into each node, with the divert key" do
    expect(node("Start.a").transition).to eq("start")
    expect(node("Ns::Work.b").transition).to eq(".expand")
    expect(node("Good.c").transition).to eq(".divert success")
    expect(node("Bad.d").transition).to eq(".divert otherwise")
    expect(node("Done.e").transition).to eq(".converge")
  end

  it "shows the class's own name" do
    expect(node("Ns::Work.b").name).to eq("Work")
  end

  it "counts steps by status with problems first and zero counts hidden" do
    2.times { step_at("Ns::Work.b", status: "completed") }
    step_at("Ns::Work.b", status: "failed")

    expect(label_texts("Ns::Work.b")).to eq(["1 failed", "2 completed"])
  end

  it "links status labels to their status" do
    step_at("Ns::Work.b", status: "in_progress")

    expect(node("Ns::Work.b").labels.first).to have_attributes(text: "1 in-progress", status: "in_progress")
  end

  it "keeps the node's own count rather than a total for the whole fan-out" do
    5.times { step_at("Ns::Work.b", status: "completed") }
    step_at("Good.c", status: "completed")

    expect(label_texts("Good.c")).to eq(["1 completed"])
  end

  it "fills the bar in proportion, keeping a tiny count visible" do
    99.times { step_at("Ns::Work.b", status: "completed") }
    step_at("Ns::Work.b", status: "failed")
    graph = described_class.new(run)
    segments = node("Ns::Work.b", graph).segments

    expect(segments.map(&:status)).to eq(%w[failed completed])
    expect(segments.first.width).to be >= 2
    expect(segments.sum(&:width)).to be_within(0.1).of(graph.bar_width)
  end

  it "separates retried steps from crash-recovered steps" do
    retried = step_at("Ns::Work.b", status: "completed")
    create(:execution, job: create(:job, step: retried), retry_count: 1)
    crashed = step_at("Ns::Work.b", status: "completed")
    job = create(:job, step: crashed)
    create(:execution, job: job, crash_count: 1)
    create(:execution, job: job, crash_count: 2)

    expect(label_texts("Ns::Work.b")).to eq(["2 completed", "1 retried", "1 crash-recovered"])
  end

  it "blames a halted branch on its latest step's node" do
    branch = create(:branch, :halted, run: run, halt_reason: "condition_unmatched")
    step_at("Start.a", branch: branch, status: "completed", started_at: 2.minutes.ago)
    step_at("Ns::Work.b", branch: branch, status: "completed", started_at: 1.minute.ago)
    run.update!(status: "halted")

    expect(label_texts("Ns::Work.b").first).to eq("1 halted: condition unmatched")
    expect(node("Ns::Work.b").state).to eq("failed")
    expect(node("Start.a").state).to eq("completed")
  end

  describe "states" do
    it "is active while a step is unfinished" do
      step_at("Start.a", status: "completed")
      step_at("Start.a", status: "pending")

      expect(node("Start.a").state).to eq("active")
    end

    it "is pending with no steps on a running pipeline" do
      expect(node("Good.c")).to have_attributes(state: "pending")
      expect(label_texts("Good.c")).to eq(["no steps yet"])
    end

    it "marks an untaken divert branch on a completed run as skipped" do
      run.update!(status: "completed")
      step_at("Bad.d", status: "completed")
      graph = described_class.new(run)

      expect(node("Good.c", graph).state).to eq("skipped")
      expect(node("Good.c", graph).labels.map(&:text)).to eq(["not taken"])
      expect(graph.edges.map(&:state)).to include("skipped", "reached")
    end

    it "does not call unreached nodes skipped on a halted run" do
      run.update!(status: "halted")

      expect(node("Good.c")).to have_attributes(state: "pending")
      expect(label_texts("Good.c")).to eq(["not reached"])
    end
  end

  it "fits the tallest node's labels in every card" do
    %w[failed in_progress waiting advancing pending completed].each do |status|
      step_at("Ns::Work.b", status:)
    end

    card_height = described_class.new(run).card_height

    expect(card_height).to eq(described_class::LABELS_TOP + 54 + described_class::CARD_BOTTOM_PADDING)
  end

  it "ignores a successor missing from the definition's nodes" do
    definition[:edges]["Start.a"][:to] = ["Ns::Work.b", "Missing.z"]

    expect(described_class.new(run).edges.length).to eq(5)
  end
end
