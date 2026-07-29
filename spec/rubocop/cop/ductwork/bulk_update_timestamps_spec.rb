# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../rubocop/cop/ductwork/bulk_update_timestamps"

RSpec.describe RuboCop::Cop::Ductwork::BulkUpdateTimestamps, :config do
  let(:ruby_version) { 3.3 }

  it "registers an offense when update_all omits updated_at" do
    expect_offense(<<~RUBY)
      Execution.where(id: id).update_all(completed_at: Time.current)
                              ^^^^^^^^^^ `update_all` skips Active Record timestamps; set `updated_at` explicitly.
    RUBY
  end

  it "registers an offense when update_columns omits updated_at" do
    expect_offense(<<~RUBY)
      execution.update_columns(process_id: process_id)
                ^^^^^^^^^^^^^^ `update_columns` skips Active Record timestamps; set `updated_at` explicitly.
    RUBY
  end

  it "registers an offense on a multiline hash" do
    expect_offense(<<~RUBY)
      Branch.where(id: id).update_all(
                           ^^^^^^^^^^ `update_all` skips Active Record timestamps; set `updated_at` explicitly.
        claim_token: nil,
        status: :in_progress
      )
    RUBY
  end

  it "accepts update_all that sets updated_at" do
    expect_no_offenses(<<~RUBY)
      Execution.where(id: id).update_all(completed_at: Time.current, updated_at: Time.current)
    RUBY
  end

  it "accepts updated_at passed with keyword shorthand" do
    expect_no_offenses(<<~RUBY)
      execution.update_columns(process_id:, updated_at:)
    RUBY
  end

  it "accepts a hash it cannot inspect statically" do
    expect_no_offenses(<<~RUBY)
      Execution.where(id: id).update_all(attributes)
    RUBY
  end

  it "accepts a hash containing a double splat" do
    expect_no_offenses(<<~RUBY)
      Execution.where(id: id).update_all(completed_at: Time.current, **timestamps)
    RUBY
  end

  it "accepts update_all called with a SQL string" do
    expect_no_offenses(<<~RUBY)
      Execution.where(id: id).update_all("crash_count = crash_count + 1")
    RUBY
  end

  it "does not flag insert_all, which stamps timestamps itself" do
    expect_no_offenses(<<~RUBY)
      Ductwork::Execution.insert_all!(execution_rows)
    RUBY
  end
end
