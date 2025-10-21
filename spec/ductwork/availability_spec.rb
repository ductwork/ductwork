# frozen_string_literal: true

RSpec.describe Ductwork::Availability do
  describe "validations" do
    let(:started_at) { Time.current }

    it "is invalid when started_at is blank" do
      availability = described_class.new

      expect(availability).not_to be_valid
      expect(availability.errors.full_messages.sole).to eq("Started at can't be blank")
    end

    it "is valid otherwise" do
      availability = described_class.new(started_at:)

      expect(availability).to be_valid
    end
  end
end
