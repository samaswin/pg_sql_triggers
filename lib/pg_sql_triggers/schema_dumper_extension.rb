# frozen_string_literal: true

module PgSqlTriggers
  # Prepended onto ActiveRecord::SchemaDumper to document that triggers live outside schema.rb.
  module SchemaDumperExtension
    def trailer(stream)
      stream.puts PgSqlTriggers::TriggerStructureDumper.schema_rb_annotation(connection: @connection) if append_notes?
      super
    end

    private

    def append_notes?
      PgSqlTriggers.append_trigger_notes_to_schema_dump &&
        defined?(Rails) &&
        Rails.application &&
        ruby_schema_format?
    end

    def ruby_schema_format?
      ar_cfg = Rails.application.config.active_record
      return true unless ar_cfg.respond_to?(:schema_format)

      format = ar_cfg.schema_format
      format.nil? || format.to_sym == :ruby
    end
  end
end
