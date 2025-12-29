# frozen_string_literal: true

class AddTimingToPgSqlTriggersRegistry < ActiveRecord::Migration[6.1]
  def change
    add_column :pg_sql_triggers_registry, :timing, :string, default: "before", null: false
    add_index :pg_sql_triggers_registry, :timing
  end
end
