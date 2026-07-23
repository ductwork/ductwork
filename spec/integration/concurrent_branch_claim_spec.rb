# frozen_string_literal: true

require "concurrent"

# NOTE: only meaningful on a concurrent RDBMS. SQLite serializes every write
# behind a single file lock, so the race cannot manifest there — the example
# skips unless run against Postgres/MySQL (e.g. `DB=postgresql bundle exec
# rspec spec/integration/concurrent_branch_claim_spec.rb`).
RSpec.describe "Concurrent branch claim", :no_transaction do
  let(:pipeline_klass) { "MyPipeline" }
  let(:definition) do
    { nodes: %w[MyStepA.0], edges: { "MyStepA.0" => { klass: "MyStepA" } } }.to_json
  end
  let(:rounds) { 100 }

  before { create(:process, :current) }

  it "grants each claimable branch to exactly one advancer under contention" do
    adapter = ActiveRecord::Base.connection.adapter_name
    skip "race is untestable on SQLite (global write lock)" if adapter.match?(/sqlite/i)

    # one worker per free pool slot; leave a slot so the main thread can still
    # set up / assert between rounds without starving a worker at the barrier.
    thread_count = [ActiveRecord::Base.connection_pool.size - 1, 2].max
    anomalies = []

    rounds.times do |round|
      run = create(:run, status: :in_progress, pipeline_klass:, definition:)
      branch = create(:branch, :in_progress, pipeline_klass:, run:)
      step = create(:step, :advancing, node: "MyStepA.0", klass: "MyStepA", branch:, run:)

      # release the main thread's connection so every pool slot is available to
      # the workers — otherwise a worker blocks on checkout and never reaches
      # the barrier, weakening (or deadlocking) the race.
      ActiveRecord::Base.connection_pool.release_connection

      barrier = Concurrent::CyclicBarrier.new(thread_count)
      threads = Array.new(thread_count) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            barrier.wait(5) # rendezvous so all claims fire as simultaneously as possible
            Ductwork::Branch.with_latest_claimed(pipeline_klass) do |b, t, a|
              b.advance!(t, a)
            end
          end
        rescue Exception => e # rubocop:disable Lint/RescueException
          e
        end
      end
      results = threads.map(&:value)

      winners = results.count { |r| r == true }
      transitions = Ductwork::Transition.where(in_step_id: step.id).count
      errors = results.grep(Exception)

      next unless winners != 1 || transitions != 1 || errors.any?

      anomalies << {
        round: round,
        winners: winners,
        transitions: transitions,
        errors: errors.map { |e| "#{e.class}: #{e.message}" }.first(3),
      }
    end

    expect(anomalies).to(
      be_empty,
      "branch claim granted more than once in #{anomalies.size}/#{rounds} " \
      "round(s): #{anomalies.first(5).inspect}"
    )
  end
end
