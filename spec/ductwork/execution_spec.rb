# frozen_string_literal: true

RSpec.describe Ductwork::Execution do
  describe "validations" do
    let(:started_at) { Time.current }

    it "is invalid when started_at is blank" do
      execution = described_class.new

      expect(execution).not_to be_valid
      expect(execution.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is valid otherwise" do
      execution = described_class.new(started_at:)

      expect(execution).to be_valid
    end
  end
end
