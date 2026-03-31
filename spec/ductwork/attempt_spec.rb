# frozen_string_literal: true

RSpec.describe Ductwork::Attempt do
  describe "validations" do
    let(:started_at) { Time.current }

    it "is invalid when started_at is blank" do
      attempt = described_class.new

      expect(attempt).not_to be_valid
      expect(attempt.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is valid otherwise" do
      attempt = described_class.new(started_at:)

      expect(attempt).to be_valid
    end
  end
end
