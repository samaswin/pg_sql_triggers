# frozen_string_literal: true

class AddConstraintDeferralToPgSqlTriggersRegistry < ActiveRecord::Migration[6.1]
  def change
    add_column :pg_sql_triggers_registry, :constraint_trigger, :boolean, default: false, null: false
    add_column :pg_sql_triggers_registry, :deferrable, :string
    add_column :pg_sql_triggers_registry, :initially, :string
  end
end
