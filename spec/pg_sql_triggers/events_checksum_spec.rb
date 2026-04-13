# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::EventsChecksum do
  describe ".canonical_from_definition" do
    it "returns empty string when events are missing" do
      expect(described_class.canonical_from_definition({})).to eq("")
    end

    it "sorts plain events for a stable checksum segment" do
      defn = { "events" => %w[update insert], "function_name" => "f" }
      expect(described_class.canonical_from_definition(defn)).to eq("insert|update")
    end

    it "includes sorted columns for update with UPDATE OF" do
      defn = { "events" => ["update"], "columns" => %w[email name] }
      expect(described_class.canonical_from_definition(defn)).to eq("update:email,name")
    end

    it "matches PostgreSQL-style multi-event clauses" do
      defn = { "events" => %w[insert update], "columns" => ["email"] }
      pg = "CREATE TRIGGER t BEFORE INSERT OR UPDATE OF email ON users FOR EACH ROW EXECUTE FUNCTION f();"
      expect(described_class.canonical_from_definition(defn))
        .to eq(described_class.canonical_from_pg_triggerdef(pg))
    end
  end

  describe ".canonical_from_pg_triggerdef" do
    it "parses UPDATE OF with multiple columns" do
      sql = 'CREATE TRIGGER t BEFORE UPDATE OF "Email", name ON users FOR EACH ROW EXECUTE FUNCTION f();'
      expect(described_class.canonical_from_pg_triggerdef(sql)).to eq("update:email,name")
    end
  end

  describe ".events_sql_fragment" do
    it "emits UPDATE OF with quoted identifiers" do
      defn = { "events" => ["update"], "columns" => %w[email] }
      sql = described_class.events_sql_fragment(defn, quote_column: ->(c) { "\"#{c}\"" })
      expect(sql).to eq('UPDATE OF "email"')
    end
  end
end
