# frozen_string_literal: true

RSpec.describe Ductwork::Configuration, "#role" do
  include ConfigurationFileHelper

  context "when the config file exists" do
    let(:data) do
      <<~DATA
        default: &default
          role: advancer

        test:
          <<: *default
      DATA
    end

    before do
      create_default_config_file
    end

    it "returns the configured role" do
      config = described_class.new

      expect(config.role).to eq("advancer")
    end
  end

  context "when passed the role in the initializer" do
    let(:data) do
      <<~DATA
        default: &default
          role: worker

        test:
          <<: *default
      DATA
    end

    before do
      create_default_config_file
    end

    it "returns the value regardless of configuration" do
      config = described_class.new(role: "supervisor")

      expect(config.role).to eq("supervisor")
    end

    it "raises if passed an invalid role" do
      config = described_class.new(role: "bogus")

      expect do
        config.role
      end.to raise_error(described_class::InvalidRoleError, "Must use a valid role")
    end
  end

  context "when no config file exists" do
    it "returns the default" do
      config = described_class.new

      expect(config.role).to eq(described_class::DEFAULT_ROLE)
    end
  end
end
