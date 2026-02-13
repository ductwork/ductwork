# frozen_string_literal: true

class MigrateTablesToUuidPrimaryKey < Ductwork::Migration
  TABLE_TO_FOREIGN_KEYS = {
    ductwork_pipelines: [],
    ductwork_steps: [:pipeline],
    ductwork_jobs: [:step],
    ductwork_executions: [:job],
    ductwork_availabilities: [:execution],
    ductwork_runs: [:execution],
    ductwork_results: [:execution],
    ductwork_tuples: [:pipeline],
    ductwork_processes: [],
  }.freeze
  FOREIGN_KEY_TO_TABLES = {
    pipeline: %i[ductwork_steps ductwork_tuples],
    step: %i[ductwork_jobs],
    job: %i[ductwork_executions],
    execution: %i[ductwork_availabilities ductwork_runs ductwork_results],
    availabilitie: [],
    run: [],
    result: [],
    tuple: [],
    processe: [],
  }.freeze

  def up
    create_primary_key_uuid_columns
    create_foreign_key_uuid_columns
    backfill_uuid_columns
    drop_old_foreign_keys
    swap_primary_keys
    swap_foreign_keys
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Cannot revert UUID migration — old integer IDs have been dropped. Restore from backup."
  end

  private

  def create_primary_key_uuid_columns
    TABLE_TO_FOREIGN_KEYS.each_key do |table|
      add_column table, :uuid, uuid_column_type
    end
  end

  def create_foreign_key_uuid_columns
    TABLE_TO_FOREIGN_KEYS.each do |table, column_prefixes|
      column_prefixes.each do |column_prefix|
        add_column table, "#{column_prefix}_uuid", uuid_column_type
      end
    end
  end

  def backfill_uuid_columns
    FOREIGN_KEY_TO_TABLES.each do |prefix, tables|
      select_all("SELECT id from ductwork_#{prefix}s WHERE uuid IS NULL").each do |row|
        uuid = connection.quote(SecureRandom.uuid_v7)
        id = row["id"]

        execute("UPDATE ductwork_#{prefix}s SET uuid = #{uuid} WHERE id = #{id}")
        tables.each do |table|
          execute("UPDATE #{table} SET #{prefix}_uuid = #{uuid} WHERE #{prefix}_id = #{id}")
        end
      end
    end
  end

  def drop_old_foreign_keys
    FOREIGN_KEY_TO_TABLES.each do |prefix, tables|
      tables.each do |table|
        remove_foreign_key table, "ductwork_#{prefix}s", column: "#{prefix}_id", if_exists: true
      end
    end
  end

  def swap_primary_keys # rubocop:disable Metrics/PerceivedComplexity
    TABLE_TO_FOREIGN_KEYS.each_key do |table|
      if postgresql?
        execute "ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{table}_pkey"
      elsif mysql?
        execute "ALTER TABLE #{table} MODIFY id BIGINT NOT NULL"
        execute "ALTER TABLE #{table} DROP PRIMARY KEY"
      end

      remove_column table, :id
      rename_column table, :uuid, :id

      if postgresql?
        execute "ALTER TABLE #{table} ADD PRIMARY KEY (id)"
      elsif mysql?
        execute "ALTER TABLE #{table} MODIFY id VARCHAR(36) NOT NULL"
        execute "ALTER TABLE #{table} ADD PRIMARY KEY (id)"
      elsif !index_exists?(table, :id)
        add_index table, :id, unique: true
      end

      change_column_null table, :id, false
    end
  end

  def swap_foreign_keys
    FOREIGN_KEY_TO_TABLES.each do |prefix, tables|
      tables.each do |table|
        remove_index table, "#{prefix}_id", if_exists: true
        remove_column table, "#{prefix}_id"
        rename_column table, "#{prefix}_uuid", "#{prefix}_id"
        if !index_exists?(table, "#{prefix}_id")
          add_index table, "#{prefix}_id"
        end
        change_column_null table, "#{prefix}_id", false
        add_foreign_key table, "ductwork_#{prefix}s", column: "#{prefix}_id"
      end
    end
  end
end
