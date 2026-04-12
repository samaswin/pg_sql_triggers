# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe PgSqlTriggers::SchemaDumperExtension do
  before do
    unless ActiveRecord::SchemaDumper.ancestors.include?(described_class)
      ActiveRecord::SchemaDumper.prepend(described_class)
    end
    PgSqlTriggers.append_trigger_notes_to_schema_dump = true
  end

  after do
    PgSqlTriggers.append_trigger_notes_to_schema_dump = true
  end

  it "appends pg_sql_triggers notes to the schema dump" do
    create(:trigger_registry, :in_sync, trigger_name: "schema_dump_note_trigger", table_name: "users")

    connection = ActiveRecord::Base.connection
    dumper = connection.create_schema_dumper(
      table_name_prefix: ActiveRecord::Base.table_name_prefix,
      table_name_suffix: ActiveRecord::Base.table_name_suffix
    )

    stream = StringIO.new
    dumper.dump(stream)

    expect(stream.string).to include("pg_sql_triggers")
    expect(stream.string).to include("schema_dump_note_trigger")
  end

  it "skips notes when append_trigger_notes_to_schema_dump is false" do
    PgSqlTriggers.append_trigger_notes_to_schema_dump = false

    connection = ActiveRecord::Base.connection
    dumper = connection.create_schema_dumper(
      table_name_prefix: ActiveRecord::Base.table_name_prefix,
      table_name_suffix: ActiveRecord::Base.table_name_suffix
    )

    stream = StringIO.new
    dumper.dump(stream)

    expect(stream.string).not_to include("pg_sql_triggers: PostgreSQL triggers are not captured in schema.rb.")
  end
end
