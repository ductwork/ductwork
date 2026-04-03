# frozen_string_literal: true

RSpec.describe Ductwork::Run do
  describe "validations" do
    let(:pipeline_klass) { "MyPipeline" }
    let(:definition) { JSON.dump({}) }
    let(:definition_sha1) { Digest::SHA1.hexdigest(definition) }
    let(:status) { described_class.statuses.keys.sample }
    let(:triggered_at) { Time.current }
    let(:started_at) { 10.minutes.from_now }

    it "is invalid if pipeline klass is blank" do
      run = described_class.new(
        definition:,
        definition_sha1:,
        status:,
        triggered_at:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Pipeline klass can't be blank")
    end

    it "is invalid if definition is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition_sha1:,
        status:,
        triggered_at:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Definition can't be blank")
    end

    it "is invalid if definition sha1 is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        status:,
        triggered_at:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Definition sha1 can't be blank")
    end

    it "is invalid if status is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        definition_sha1:,
        triggered_at:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Status can't be blank")
    end

    it "is invalid if triggered at is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        definition_sha1:,
        status:,
        started_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Triggered at can't be blank")
    end

    it "is invalid if started at is blank" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        definition_sha1:,
        status:,
        triggered_at:
      )

      expect(run).not_to be_valid
      expect(run.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is valid otherwise" do
      run = described_class.new(
        pipeline_klass:,
        definition:,
        definition_sha1:,
        status:,
        triggered_at:,
        started_at:
      )

      expect(run).to be_valid
    end
  end

  describe "#parsed_definition" do
    it "returns a JSON parsed indifferent hash" do
      run = described_class.new(definition: JSON.dump({ foo: "bar" }))

      expect(run.parsed_definition[:foo]).to eq("bar")
      expect(run.parsed_definition["foo"]).to eq("bar")
    end
  end
end
