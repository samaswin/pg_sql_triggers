# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Migrator::PreApplyComparator do
  describe ".compare" do
    let(:migration_instance) do
      Class.new(PgSqlTriggers::Migration) do
        def up
          execute "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
          execute "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
        end
      end.new
    end

    it "compares expected state with actual state" do
      result = described_class.compare(migration_instance, direction: :up)
      expect(result).to be_a(Hash)
      expect(result).to have_key(:functions)
      expect(result).to have_key(:triggers)
    end

    it "handles down direction" do
      migration_down = Class.new(PgSqlTriggers::Migration) do
        def down
          execute "DROP TRIGGER IF EXISTS test_trigger ON users;"
          execute "DROP FUNCTION IF EXISTS test_func();"
        end
      end.new

      result = described_class.compare(migration_down, direction: :down)
      expect(result).to be_a(Hash)
    end
  end
end

