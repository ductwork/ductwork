# frozen_string_literal: true

RSpec.describe Ductwork::Tuple do
  let(:key) { "key" }
  let(:value) { "value" }
  let(:first_set_at) { 1.hour.ago }
  let(:last_set_at) { Time.current }

  describe "validations" do
    it "is invalid if the key is blank" do
      key = "                       "

      tuple = described_class.new(key:, first_set_at:, last_set_at:)

      expect(tuple).not_to be_valid
      expect(tuple.errors.full_messages).to eq(["Key can't be blank"])
    end

    it "is invalid if the first set at is blank" do
      first_set_at = nil

      tuple = described_class.new(key:, first_set_at:, last_set_at:)

      expect(tuple).not_to be_valid
      expect(tuple.errors.full_messages).to eq(["First set at can't be blank"])
    end

    it "is invalid if the last set at is blank" do
      last_set_at = nil

      tuple = described_class.new(key:, first_set_at:, last_set_at:)

      expect(tuple).not_to be_valid
      expect(tuple.errors.full_messages).to eq(["Last set at can't be blank"])
    end

    it "is invalid if the key and run id are already taken" do
      run = create(:run)
      described_class.create!(run:, key:, first_set_at:, last_set_at:)

      tuple = described_class.new(run:, key:, first_set_at:, last_set_at:)

      expect(tuple).not_to be_valid
      expect(tuple.errors.full_messages).to eq(["Key has already been taken"])
    end

    it "is valid otherwise" do
      tuple = described_class.new(key:, first_set_at:, last_set_at:)

      expect(tuple).to be_valid
    end
  end

  describe "#value=" do
    subject(:tuple) { described_class.new(value:) }

    it "serializes the value" do
      expect(tuple.serialized_value).to eq({ raw_value: value }.to_json)
    end
  end

  describe "#value" do
    it "returns nil if no value is set" do
      tuple = described_class.new

      expect(tuple.value).to be_nil
    end

    it "deserializes the value" do
      tuple = described_class.new(value: "value")

      expect(tuple.value).to eq("value")
    end
  end
end
