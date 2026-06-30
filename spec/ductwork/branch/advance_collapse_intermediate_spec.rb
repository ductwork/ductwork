# frozen_string_literal: true

# Regression coverage for the collapse fan-in when the siblings are NOT direct
# children of the expanding branch. Before the `barrier_node` resolver,
# `collapse_branch` keyed off the immediate parent; with any branch-creating
# transition (`divide`/`combine`) or a nested `expand` between the `expand` and
# `collapse`, the immediate parent was not the expanding branch, so each sibling
# saw only itself, judged the fan-in complete, and minted its own collapse
# target. These prove a single target is produced, fed by every sibling.
RSpec.describe Ductwork::Branch, "#advance collapse intermediate" do
  let(:run) { create(:run, status: :in_progress, definition: definition) }
  let(:user_count) { 2 }
  let(:barrier_branch) { create(:branch, :completed, run:) }

  before do
    create(:process, :current)
    create(
      :step,
      :completed,
      node: "Query.0",
      klass: "Query",
      run: run,
      branch: barrier_branch
    )
  end

  def advance_all(siblings)
    siblings.each do |sibling|
      transition = create(:transition, branch: sibling)
      advancement = create(:advancement, transition:)
      sibling.advance!(transition, advancement)
    end
  end

  context "with expand -> divide -> combine -> collapse" do
    let(:definition) do
      {
        nodes: %w[
          Query.0 LoadUserData.1 FetchA.2 FetchB.3
          CollateUserData.4 UpdateUserData.5 Report.6
        ],
        edges: {
          "Query.0" => { to: %w[LoadUserData.1], type: "expand", klass: "Query" },
          "LoadUserData.1" => {
            to: %w[FetchA.2 FetchB.3], type: "divide", klass: "LoadUserData",
          },
          "FetchA.2" => { to: %w[CollateUserData.4], type: "combine", klass: "FetchA" },
          "FetchB.3" => { to: %w[CollateUserData.4], type: "combine", klass: "FetchB" },
          "CollateUserData.4" => {
            to: %w[UpdateUserData.5], type: "chain", klass: "CollateUserData",
          },
          "UpdateUserData.5" => {
            to: %w[Report.6],
            type: "collapse",
            klass: "UpdateUserData",
            barrier_node: "Query.0",
          },
          "Report.6" => { klass: "Report" },
        },
      }.to_json
    end

    def build_user_chain(value)
      load_branch = create(:branch, :completed, run:)
      Ductwork::BranchLink.create!(parent_branch: barrier_branch, child_branch: load_branch)
      # the expand child ran the `expand` target node (drives the expected count)
      create(:step, :completed, node: "LoadUserData.1", klass: "LoadUserData", run: run, branch: load_branch)

      fetch_a = create(:branch, :completed, run:)
      fetch_b = create(:branch, :completed, run:)
      Ductwork::BranchLink.create!(parent_branch: load_branch, child_branch: fetch_a)
      Ductwork::BranchLink.create!(parent_branch: load_branch, child_branch: fetch_b)

      collapsing = create(:branch, :in_progress, run:)
      Ductwork::BranchLink.create!(parent_branch: fetch_a, child_branch: collapsing)
      Ductwork::BranchLink.create!(parent_branch: fetch_b, child_branch: collapsing)

      step = create(
        :step,
        status: :advancing,
        node: "UpdateUserData.5",
        klass: "UpdateUserData",
        run: run,
        branch: collapsing
      )
      create(:job, output_payload: { payload: value }.to_json, step: step)

      collapsing
    end

    it "creates exactly one collapse target fed by every sibling" do
      siblings = [build_user_chain(10), build_user_chain(20)]
      allow(Ductwork::Job).to receive(:enqueue).and_call_original

      expect do
        advance_all(siblings)
      end.to change(Ductwork::Step.where(node: "Report.6"), :count).by(1)

      target = Ductwork::Step.find_by(node: "Report.6").branch
      expect(target.parent_branches.count).to eq(user_count)
      expect(Ductwork::Job).to have_received(:enqueue).with(anything, contain_exactly(10, 20))
    end
  end

  context "with nested expand -> expand -> collapse -> collapse" do
    let(:definition) do
      {
        nodes: %w[Query.0 Inner.1 Leaf.2 InnerReport.3 OuterReport.4],
        edges: {
          "Query.0" => { to: %w[Inner.1], type: "expand", klass: "Query" },
          "Inner.1" => { to: %w[Leaf.2], type: "expand", klass: "Inner" },
          "Leaf.2" => {
            to: %w[InnerReport.3], type: "collapse", klass: "Leaf", barrier_node: "Inner.1",
          },
          "InnerReport.3" => {
            to: %w[OuterReport.4],
            type: "collapse",
            klass: "InnerReport",
            barrier_node: "Query.0",
          },
          "OuterReport.4" => { klass: "OuterReport" },
        },
      }.to_json
    end

    # the OUTER collapse sibling sits below an inner-`expand` branch (node
    # `Inner.1`). The resolver must skip that branch — its node is not the outer
    # `barrier_node` — and walk on to `Query.0`.
    def build_outer_sibling(value)
      inner_expand = create(:branch, :completed, run:)
      Ductwork::BranchLink.create!(parent_branch: barrier_branch, child_branch: inner_expand)
      create(:step, :completed, node: "Inner.1", klass: "Inner", run: run, branch: inner_expand)

      inner_collapse = create(:branch, :completed, run:)
      Ductwork::BranchLink.create!(parent_branch: inner_expand, child_branch: inner_collapse)

      outer_sibling = create(:branch, :in_progress, run:)
      Ductwork::BranchLink.create!(parent_branch: inner_collapse, child_branch: outer_sibling)
      step = create(
        :step,
        status: :advancing,
        node: "InnerReport.3",
        klass: "InnerReport",
        run: run,
        branch: outer_sibling
      )
      create(:job, output_payload: { payload: value }.to_json, step: step)

      outer_sibling
    end

    it "resolves the outer barrier past the inner expand and creates one target" do
      siblings = [build_outer_sibling(1), build_outer_sibling(2)]
      allow(Ductwork::Job).to receive(:enqueue).and_call_original

      expect do
        advance_all(siblings)
      end.to change(Ductwork::Step.where(node: "OuterReport.4"), :count).by(1)

      target = Ductwork::Step.find_by(node: "OuterReport.4").branch
      expect(target.parent_branches.count).to eq(user_count)
      expect(Ductwork::Job).to have_received(:enqueue).with(anything, contain_exactly(1, 2))
    end
  end
end
