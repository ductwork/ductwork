# frozen_string_literal: true

module Ductwork
  # NOTE: these are SQL fragments that resolve against the database server's
  # clock instead of the calling Ruby process's clock. use them in `WHERE`
  # clauses that compare between a stored timestamp and "now" so that NTP
  # drift between hosts cannot make healthy work look stale (or vice versa)
  class DatabaseClock
    def self.ago_sql(column, interval)
      new(column).ago_sql(interval)
    end

    def self.now_sql(column)
      new(column).now_sql
    end

    def self.now
      new.now
    end

    def initialize(column = nil)
      @adapter = Ductwork::Record.connection.adapter_name.downcase
      @column = column
    end

    def ago_sql(interval)
      seconds = interval.to_i

      case adapter
      when /postgresql|cockroach/i
        "#{column} <= clock_timestamp() - INTERVAL '#{seconds} seconds'"
      when /mysql|trilogy/i
        "#{column} <= CURRENT_TIMESTAMP(6) - INTERVAL #{seconds} SECOND"
      when /sqlite/i
        "julianday(#{column}) <= julianday('now', '-#{seconds} seconds')"
      when /oracle/i
        "#{column} <= CURRENT_TIMESTAMP - NUMTODSINTERVAL(#{seconds}, 'SECOND')"
      else
        raise NotImplementedError, "Database clock does not support adapter #{adapter}"
      end
    end

    def now_sql
      case adapter
      when /sqlite/i
        "julianday(#{column}) <= julianday('now')"
      when /mysql|trilogy/i
        "#{column} <= CURRENT_TIMESTAMP(6)"
      when /postgresql|cockroach/i
        "#{column} <= clock_timestamp()"
      when /oracle/i
        "#{column} <= CURRENT_TIMESTAMP"
      else
        raise NotImplementedError, "Database clock does not support adapter #{adapter}"
      end
    end

    def now
      raw = Ductwork::Record.connection.select_value(now_select_sql)

      case raw
      when ::Time, ::DateTime
        raw.in_time_zone
      else
        # NOTE: SQLite returns an ISO-8601 string already expressed in UTC
        ::Time.find_zone!("UTC").parse(raw.to_s)
      end
    end

    private

    attr_reader :adapter, :column

    def now_select_sql
      case adapter
      when /postgresql|cockroach/i
        "SELECT clock_timestamp()"
      when /mysql|trilogy/i
        "SELECT CURRENT_TIMESTAMP(6)"
      when /sqlite/i
        "SELECT strftime('%Y-%m-%d %H:%M:%f', 'now')"
      when /oracle/i
        "SELECT CURRENT_TIMESTAMP FROM dual"
      else
        raise NotImplementedError, "Database clock does not support adapter #{adapter}"
      end
    end
  end
end
