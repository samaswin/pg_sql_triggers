# frozen_string_literal: true

class CreatePgTriggersTables < ActiveRecord::Migration[6.0]
  def change
    # Registry table - source of truth for all triggers
    create_table :pg_triggers_registry do |t|
      t.string :trigger_name, null: false
      t.string :table_name, null: false
      t.integer :version, null: false, default: 1
      t.boolean :enabled, null: false, default: false
      t.string :checksum, null: false
      t.string :source, null: false # dsl, generated, manual_sql
      t.string :environment
      t.text :definition # Stored DSL or SQL definition
      t.text :function_body # The actual function body
      t.text :condition # Optional WHEN clause condition
      t.datetime :installed_at
      t.datetime :last_verified_at

      t.timestamps
    end

    add_index :pg_triggers_registry, :trigger_name, unique: true
    add_index :pg_triggers_registry, :table_name
    add_index :pg_triggers_registry, :enabled
    add_index :pg_triggers_registry, :source
    add_index :pg_triggers_registry, :environment

    # Trigger migrations table - tracks which trigger migrations have been run
    create_table :trigger_migrations do |t|
      t.string :version, null: false
    end

    add_index :trigger_migrations, :version, unique: true
  end
end
