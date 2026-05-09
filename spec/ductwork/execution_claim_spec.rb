# frozen_string_literal: true

RSpec.describe Ductwork::ExecutionClaim do
  describe "latest" do
    let(:klass) { "MyPipeline" }
    let(:owner_process_id) { SecureRandom.uuid }

    context "when the database adapter is postgresql" do
      before do
        use_db_adapter("PostgreSQL")
      end

      it "calls the row locking job claim class" do
        claim = instance_double(Ductwork::RowLockingExecutionClaim, latest: nil)
        allow(Ductwork::RowLockingExecutionClaim).to receive(:new).and_return(claim)

        described_class.new(klass, owner_process_id).latest

        expect(Ductwork::RowLockingExecutionClaim).to have_received(:new).with(
          klass,
          owner_process_id
        )
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is mysql2" do
      before do
        use_db_adapter("MySQL2")
      end

      it "calls the row locking job claim class" do
        claim = instance_double(Ductwork::RowLockingExecutionClaim, latest: nil)
        allow(Ductwork::RowLockingExecutionClaim).to receive(:new).and_return(claim)

        described_class.new(klass, owner_process_id).latest

        expect(Ductwork::RowLockingExecutionClaim).to have_received(:new).with(
          klass,
          owner_process_id
        )
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is trilogy" do
      before do
        use_db_adapter("Trilogy")
      end

      it "calls the row locking job claim class" do
        claim = instance_double(Ductwork::RowLockingExecutionClaim, latest: nil)
        allow(Ductwork::RowLockingExecutionClaim).to receive(:new).and_return(claim)

        described_class.new(klass, owner_process_id).latest

        expect(Ductwork::RowLockingExecutionClaim).to have_received(:new).with(
          klass,
          owner_process_id
        )
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is mysql" do
      before do
        use_db_adapter("MySQL")
      end

      it "calls the optimistic locking job claim class" do
        claim = instance_double(Ductwork::OptimisticLockingExecutionClaim, latest: nil)
        allow(Ductwork::OptimisticLockingExecutionClaim).to receive(:new).and_return(claim)

        described_class.new(klass, owner_process_id).latest

        expect(Ductwork::OptimisticLockingExecutionClaim).to have_received(:new).with(
          klass,
          owner_process_id
        )
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is sqlite" do
      before do
        use_db_adapter("SQLite")
      end

      it "calls the optimistic locking job claim class" do
        claim = instance_double(Ductwork::OptimisticLockingExecutionClaim, latest: nil)
        allow(Ductwork::OptimisticLockingExecutionClaim).to receive(:new).and_return(claim)

        described_class.new(klass, owner_process_id).latest

        expect(Ductwork::OptimisticLockingExecutionClaim).to have_received(:new).with(
          klass,
          owner_process_id
        )
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is cockroachdb" do
      before do
        use_db_adapter("CockroachDB")
      end

      it "calls the optimistic locking job claim class" do
        claim = instance_double(Ductwork::OptimisticLockingExecutionClaim, latest: nil)
        allow(Ductwork::OptimisticLockingExecutionClaim).to receive(:new).and_return(claim)

        described_class.new(klass, owner_process_id).latest

        expect(Ductwork::OptimisticLockingExecutionClaim).to have_received(:new).with(
          klass,
          owner_process_id
        )
        expect(claim).to have_received(:latest)
      end
    end

    def use_db_adapter(adapter_name)
      allow(Ductwork::Record.connection).to receive(:adapter_name)
        .and_return(adapter_name)
    end
  end
end
