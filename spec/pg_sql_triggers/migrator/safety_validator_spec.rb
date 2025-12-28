# frozen_string_literal: true

require "spec_helper"

RSpec.describe PgSqlTriggers::Migrator::SafetyValidator do
  describe ".validate!" do
    context "when migration is safe" do
      let(:safe_migration) do
        Class.new(PgSqlTriggers::Migration) do
          def up
            execute "CREATE OR REPLACE FUNCTION test_func() RETURNS TRIGGER AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
            execute "CREATE TRIGGER test_trigger BEFORE INSERT ON users FOR EACH ROW EXECUTE FUNCTION test_func();"
          end
        end.new
      end

      it "does not raise error for safe migration" do
        expect do
          described_class.validate!(safe_migration, direction: :up, allow_unsafe: false)
        end.not_to raise_error
      end

      it "does not raise error when allow_unsafe is true" do
        expect do
          described_class.validate!(safe_migration, direction: :up, allow_unsafe: true)
        end.not_to raise_error
      end

      it "handles down direction" do
        migration_down = Class.new(PgSqlTriggers::Migration) do
          def down
            execute "DROP TRIGGER IF EXISTS test_trigger ON users;"
            execute "DROP FUNCTION IF EXISTS test_func();"
          end
        end.new

        expect do
          described_class.validate!(migration_down, direction: :down, allow_unsafe: false)
        end.not_to raise_error
      end
    end
  end
end

