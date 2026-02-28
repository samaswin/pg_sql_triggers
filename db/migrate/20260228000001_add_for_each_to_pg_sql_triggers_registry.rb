# frozen_string_literal: true

class AddForEachToPgSqlTriggersRegistry < ActiveRecord::Migration[6.1]
  def change
    add_column :pg_sql_triggers_registry, :for_each, :string, default: "row", null: false
    add_index :pg_sql_triggers_registry, :for_each
  end
end
