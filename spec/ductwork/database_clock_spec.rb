# frozen_string_literal: true

RSpec.describe Ductwork::DatabaseClock do
  describe ".ago_sql" do
    before do
      allow(Ductwork::Record.connection).to receive(:adapter_name).and_return(adapter)
    end

    context "with the PostgreSQL adapter" do
      let(:adapter) { "pOsTgReSqL" }

      it "returns a valid string" do
        sql = described_class.ago_sql("last_heartbeat_at", 1.second)

        expect(sql).to eq("last_heartbeat_at <= clock_timestamp() - INTERVAL '1 seconds'")
      end
    end

    context "with the CockroachDB adapter" do
      let(:adapter) { "cockroachdb" }

      it "returns a valid string" do
        sql = described_class.ago_sql("last_heartbeat_at", 5.minutes)

        expect(sql).to eq("last_heartbeat_at <= clock_timestamp() - INTERVAL '300 seconds'")
      end
    end

    context "with the MySQL adapter" do
      let(:adapter) { "MySQL" }

      it "returns a valid string" do
        sql = described_class.ago_sql("last_heartbeat_at", 2.minutes)

        expect(sql).to eq("last_heartbeat_at <= CURRENT_TIMESTAMP(6) - INTERVAL 120 SECOND")
      end
    end

    context "with the Trilogy adapter" do
      let(:adapter) { "trilogy" }

      it "returns a valid string" do
        sql = described_class.ago_sql("last_heartbeat_at", 30.seconds)

        expect(sql).to eq("last_heartbeat_at <= CURRENT_TIMESTAMP(6) - INTERVAL 30 SECOND")
      end
    end

    context "with the SQLite adapter" do
      let(:adapter) { "SQLite" }

      it "returns a valid string" do
        sql = described_class.ago_sql("last_heartbeat_at", 1.hour)

        expect(sql).to eq("julianday(last_heartbeat_at) <= julianday('now', '-3600 seconds')")
      end
    end

    context "with the Oracle adapter" do
      let(:adapter) { "oracle" }

      it "returns a valid string" do
        sql = described_class.ago_sql("last_heartbeat_at", 5.seconds)

        expect(sql).to eq("last_heartbeat_at <= CURRENT_TIMESTAMP - NUMTODSINTERVAL(5, 'SECOND')")
      end
    end

    context "with an unsupported adapter" do
      let(:adapter) { "MongoDB" }

      it "raises an error" do
        expect do
          described_class.ago_sql("last_heartbeat_at", 4.days)
        end.to raise_error(
          NotImplementedError,
          "Database clock does not support adapter mongodb"
        )
      end
    end
  end

  describe ".now_sql" do
    before do
      allow(Ductwork::Record.connection).to receive(:adapter_name).and_return(adapter)
    end

    context "with the SQLite adapter" do
      let(:adapter) { "SQLite" }

      it "returns a valid string" do
        sql = described_class.now_sql("started_at")

        expect(sql).to eq("julianday(started_at) <= julianday('now')")
      end
    end

    context "with the MySQL adapter" do
      let(:adapter) { "MySQL" }

      it "returns a valid string" do
        sql = described_class.now_sql("started_at")

        expect(sql).to eq("started_at <= CURRENT_TIMESTAMP(6)")
      end
    end

    context "with the CockroachDB adapter" do
      let(:adapter) { "cockroachdb" }

      it "returns a valid string" do
        sql = described_class.now_sql("started_at")

        expect(sql).to eq("started_at <= clock_timestamp()")
      end
    end

    context "with an unsupported adapter" do
      let(:adapter) { "MongoDB" }

      it "raises an error" do
        expect do
          described_class.ago_sql("last_heartbeat_at", 4.days)
        end.to raise_error(
          NotImplementedError,
          "Database clock does not support adapter mongodb"
        )
      end
    end
  end

  describe ".now" do
    it "returns the database server's current time as a Time" do
      now = described_class.now

      expect(now).to be_a(ActiveSupport::TimeWithZone).or be_a(Time)
      expect(now).to be_within(5.seconds).of(Time.current)
    end

    context "with an unsupported adapter" do
      before do
        allow(Ductwork::Record.connection).to receive(:adapter_name).and_return("MongoDB")
      end

      it "raises an error" do
        expect do
          described_class.now
        end.to raise_error(
          NotImplementedError,
          "Database clock does not support adapter mongodb"
        )
      end
    end
  end
end
