# frozen_string_literal: true

RSpec.describe Ductwork::JobClaim do
  describe "latest" do
    let(:klass) { "MyPipeline" }

    context "when the database adapter is postgresql" do
      before do
        use_db_adapter("PostgreSQL")
      end

      it "calls the row locking job claim class" do
        claim = instance_double(Ductwork::RowLockingJobClaim, latest: nil)
        allow(Ductwork::RowLockingJobClaim).to receive(:new).and_return(claim)

        described_class.new(klass).latest

        expect(Ductwork::RowLockingJobClaim).to have_received(:new).with(klass)
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is mysql2" do
      before do
        use_db_adapter("MySQL2")
      end

      it "calls the row locking job claim class" do
        claim = instance_double(Ductwork::RowLockingJobClaim, latest: nil)
        allow(Ductwork::RowLockingJobClaim).to receive(:new).and_return(claim)

        described_class.new(klass).latest

        expect(Ductwork::RowLockingJobClaim).to have_received(:new).with(klass)
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is trilogy" do
      before do
        use_db_adapter("Trilogy")
      end

      it "calls the row locking job claim class" do
        claim = instance_double(Ductwork::RowLockingJobClaim, latest: nil)
        allow(Ductwork::RowLockingJobClaim).to receive(:new).and_return(claim)

        described_class.new(klass).latest

        expect(Ductwork::RowLockingJobClaim).to have_received(:new).with(klass)
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is mysql" do
      before do
        use_db_adapter("MySQL")
      end

      it "calls the optimistic locking job claim class" do
        claim = instance_double(Ductwork::OptimisticLockingJobClaim, latest: nil)
        allow(Ductwork::OptimisticLockingJobClaim).to receive(:new).and_return(claim)

        described_class.new(klass).latest

        expect(Ductwork::OptimisticLockingJobClaim).to have_received(:new).with(klass)
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is sqlite" do
      before do
        use_db_adapter("SQLite")
      end

      it "calls the optimistic locking job claim class" do
        claim = instance_double(Ductwork::OptimisticLockingJobClaim, latest: nil)
        allow(Ductwork::OptimisticLockingJobClaim).to receive(:new).and_return(claim)

        described_class.new(klass).latest

        expect(Ductwork::OptimisticLockingJobClaim).to have_received(:new).with(klass)
        expect(claim).to have_received(:latest)
      end
    end

    context "when the database adapter is cockroachdb" do
      before do
        use_db_adapter("CockroachDB")
      end

      it "calls the optimistic locking job claim class" do
        claim = instance_double(Ductwork::OptimisticLockingJobClaim, latest: nil)
        allow(Ductwork::OptimisticLockingJobClaim).to receive(:new).and_return(claim)

        described_class.new(klass).latest

        expect(Ductwork::OptimisticLockingJobClaim).to have_received(:new).with(klass)
        expect(claim).to have_received(:latest)
      end
    end

    def use_db_adapter(adapter_name)
      allow(Ductwork::Record.connection).to receive(:adapter_name)
        .and_return(adapter_name)
    end
  end
end
