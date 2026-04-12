# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe PgSqlTriggers::TriggerStructureDumper do
  let(:connection) { ActiveRecord::Base.connection }

  describe ".resolve_path" do
    it "defaults to db/trigger_structure.sql under Rails.root" do
      path = described_class.resolve_path(nil)
      expect(path.to_s).to end_with("db/trigger_structure.sql")
    end

    it "respects a string override" do
      Dir.mktmpdir do |dir|
        override = File.join(dir, "custom.sql")
        expect(described_class.resolve_path(override).to_s).to eq(override)
      end
    end
  end

  describe ".generate_sql" do
    let(:trigger_name) { "pg_sql_triggers_dump_spec_tr" }
    let(:function_name) { "pg_sql_triggers_dump_spec_fn" }

    def create_db_trigger
      connection.execute(<<~SQL.squish)
        CREATE OR REPLACE FUNCTION #{function_name}()
        RETURNS trigger AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;
      SQL
      connection.execute(<<~SQL.squish)
        DROP TRIGGER IF EXISTS #{trigger_name} ON pg_sql_triggers_registry;
        CREATE TRIGGER #{trigger_name}
        BEFORE INSERT ON pg_sql_triggers_registry
        FOR EACH ROW
        EXECUTE FUNCTION #{function_name}();
      SQL
    end

    def drop_db_trigger
      connection.execute("DROP TRIGGER IF EXISTS #{trigger_name} ON pg_sql_triggers_registry;")
      connection.execute("DROP FUNCTION IF EXISTS #{function_name}();")
    end

    around do |example|
      drop_db_trigger
      example.run
    ensure
      drop_db_trigger
      PgSqlTriggers::TriggerRegistry.where(trigger_name: trigger_name).delete_all
    end

    it "includes function and trigger DDL for a registered trigger" do
      create_db_trigger
      create(
        :trigger_registry,
        :in_sync,
        trigger_name: trigger_name,
        table_name: "pg_sql_triggers_registry",
        source: "manual_sql"
      )

      sql = described_class.generate_sql(connection: connection)
      expect(sql).to include(trigger_name)
      expect(sql).to include("CREATE TRIGGER")
      expect(sql).to include("CREATE OR REPLACE FUNCTION")
    end
  end

  describe ".load_from" do
    it "runs SQL from a file" do
      Tempfile.create(%w[triggers .sql]) do |file|
        file.write("SELECT 1 AS pg_sql_triggers_load_spec;\n")
        file.flush
        expect { described_class.load_from(file.path) }.not_to raise_error
      end
    end
  end

  describe ".schema_rb_annotation" do
    it "mentions pg_sql_triggers and lists managed trigger names" do
      create(:trigger_registry, :in_sync, trigger_name: "annotation_list_trigger", table_name: "users")
      text = described_class.schema_rb_annotation(connection: connection)
      expect(text).to include("pg_sql_triggers")
      expect(text).to include("annotation_list_trigger")
    end
  end
end
