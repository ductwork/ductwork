# frozen_string_literal: true

RSpec.describe Ductwork::Branch, "#advance!" do
  subject(:branch) { pipeline.current_run.branches.sole }

  let(:pipeline) { MyPipeline.trigger(1) }
  let(:skew) { 1.hour }

  before do
    create(:process, :current)
    allow(Ductwork.logger).to receive(:warn)
  end

  it "advances a branch whose first step was stamped by a fast host" do
    on_fast_host { pipeline }
    transition, advancement = ready_latest_step_for_advancing

    expect do
      branch.advance!(transition, advancement)
    end.to change { branch.steps.count }.by(1)

    expect(branch.latest_step.klass).to eq("MySecondStep")
    expect(Ductwork.logger).not_to have_received(:warn).with(
      hash_including(msg: "Branch claimed with no step to advance, released")
    )
  end

  it "advances a branch whose intermediate step was stamped by a fast host" do
    pipeline
    on_fast_host { branch.advance!(*ready_latest_step_for_advancing) }
    transition, advancement = ready_latest_step_for_advancing

    expect do
      branch.advance!(transition, advancement)
    end.to change { branch.steps.count }.by(1)

    expect(branch.latest_step.klass).to eq("MyThirdStep")
    expect(Ductwork.logger).not_to have_received(:warn).with(
      hash_including(msg: "Branch claimed with no step to advance, released")
    )
  end

  def on_fast_host(&block)
    travel_to(Time.current + skew, &block)
  end

  def ready_latest_step_for_advancing
    step = branch.latest_step
    step.update!(status: :advancing)
    step.job.update!(output_payload: { payload: 2 }.to_json)
    transition = create(:transition, branch:)

    [transition, create(:advancement, transition:)]
  end
end
