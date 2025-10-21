# frozen_string_literal: true

RSpec.describe Ductwork::Job do
  describe "validations" do
    let(:klass) { "MyFirstJob" }
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
end
