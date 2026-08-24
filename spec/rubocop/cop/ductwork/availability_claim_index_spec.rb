# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../rubocop/cop/ductwork/availability_claim_index"

RSpec.describe RuboCop::Cop::Ductwork::AvailabilityClaimIndex, :config do
  let(:ruby_version) { 3.3 }

  it "registers an offense when add_index names the claim index" do
    expect_offense(<<~RUBY)
      add_index :ductwork_availabilities,
                %i[pipeline_klass started_at],
                name: "index_ductwork_availabilities_on_claim_latest",
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not name the availability claim index directly; use `Ductwork::MigrationHelper`'s claim index helpers.
                where: "completed_at IS NULL"
    RUBY
  end

  it "registers an offense when remove_index names the claim index" do
    expect_offense(<<~RUBY)
      remove_index :ductwork_availabilities, name: "index_ductwork_availabilities_on_claim_latest"
                                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not name the availability claim index directly; use `Ductwork::MigrationHelper`'s claim index helpers.
    RUBY
  end

  it "registers an offense when the name is checked for existence" do
    expect_offense(<<~RUBY)
      connection.index_exists?(:ductwork_availabilities, name: "index_ductwork_availabilities_on_claim_latest")
                                                               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not name the availability claim index directly; use `Ductwork::MigrationHelper`'s claim index helpers.
    RUBY
  end

  it "registers an offense when the name is written as a symbol" do
    expect_offense(<<~RUBY)
      remove_index :ductwork_availabilities, name: :index_ductwork_availabilities_on_claim_latest
                                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not name the availability claim index directly; use `Ductwork::MigrationHelper`'s claim index helpers.
    RUBY
  end

  it "accepts the helper that builds the index" do
    expect_no_offenses(<<~RUBY)
      add_availability_claim_index(extra_columns: [:limit_key], where_extra: "limit_key IS NULL")
    RUBY
  end

  it "accepts the helper that removes the index" do
    expect_no_offenses(<<~RUBY)
      remove_availability_claim_index
    RUBY
  end

  it "accepts a reference through the constant" do
    expect_no_offenses(<<~RUBY)
      connection.index_exists?(
        :ductwork_availabilities,
        name: Ductwork::MigrationHelper::AVAILABILITY_CLAIM_INDEX_NAME
      )
    RUBY
  end

  it "accepts other ductwork index names" do
    expect_no_offenses(<<~RUBY)
      add_index :ductwork_transitions,
                %i[run_id completed_at],
                name: "index_ductwork_transitions_on_latest_open"
    RUBY
  end
end
