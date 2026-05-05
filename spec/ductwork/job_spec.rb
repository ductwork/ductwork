# frozen_string_literal: true

RSpec.describe Ductwork::Job do
  describe "validations" do
    let(:klass) { "MyFirstStep" }
    let(:started_at) { Time.current }
    let(:input_args) { 1 }

    it "is invalid when klass is blank" do
      job = described_class.new(started_at:, input_args:)

      expect(job).not_to be_valid
      expect(job.errors.full_messages).to eq(["Klass can't be blank"])
    end

    it "is invalid when started_at is blank" do
      job = described_class.new(klass:, input_args:)

      expect(job).not_to be_valid
      expect(job.errors.full_messages).to eq(["Started at can't be blank"])
    end

    it "is invalid when input_args is blank" do
      job = described_class.new(klass:, started_at:)

      expect(job).not_to be_valid
      expect(job.errors.full_messages).to eq(["Input args can't be blank"])
    end

    it "is valid otherwise" do
      job = described_class.new(klass:, started_at:, input_args:)

      expect(job).to be_valid
    end
  end

  describe ".enqueue" do
    let(:step) { create(:step) }
    let(:args) { %i[foo bar] }

    it "creates a job record" do
      expect do
        described_class.enqueue(step, args)
      end.to change(described_class, :count).by(1)
        .and change(step, :job).from(nil)

      job = described_class.sole
      expect(job.klass).to eq("MyFirstStep")
      expect(job.started_at).to be_almost_now
      expect(job.completed_at).to be_nil
      expect(job.input_args).to eq(JSON.dump({ args: [args] }))
      expect(job.output_payload).to be_nil
      expect(job.step).to eq(step)
    end

    it "creates an execution record" do
      expect do
        described_class.enqueue(step, args)
      end.to change(Ductwork::Execution, :count).by(1)

      job = described_class.sole
      execution = job.executions.sole
      expect(execution.started_at).to be_almost_now
      expect(execution.completed_at).to be_nil
    end

    it "creates an availability record" do
      expect do
        described_class.enqueue(step, args)
      end.to change(Ductwork::Availability, :count).by(1)

      execution = Ductwork::Execution.sole
      availability = execution.availability
      expect(availability.started_at).to be_almost_now
      expect(availability.completed_at).to be_nil
    end
  end

  describe "#return_value" do
    subject(:job) { described_class.new(output_payload:) }

    let(:output_payload) { { payload: }.to_json }

    context "when the output payload holds a nil value" do
      let(:payload) { nil }

      it "returns nil" do
        expect(job.return_value).to be_nil
      end
    end

    context "when the output payload holds values" do
      let(:payload) { %w[a b c] }

      it "returns the value" do
        expect(job.return_value).to eq(%w[a b c])
      end
    end

    context "when the output payload is nil" do
      let(:output_payload) { nil }

      it "returns nil" do
        expect(job.return_value).to be_nil
      end
    end
  end
end
