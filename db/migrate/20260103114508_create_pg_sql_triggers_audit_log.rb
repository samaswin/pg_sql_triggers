# frozen_string_literal: true

class CreatePgSqlTriggersAuditLog < ActiveRecord::Migration[6.1]
  def change
    create_table :pg_sql_triggers_audit_log do |t|
      t.string :trigger_name
      t.string :operation, null: false
      t.jsonb :actor # Store actor information (type, id)
      t.string :environment
      t.string :status, null: false # success, failure
      t.text :reason
      t.string :confirmation_text
      t.jsonb :before_state # Store state before operation
      t.jsonb :after_state # Store state after operation
      t.text :diff # Store diff if applicable
      t.text :error_message # Store error message if operation failed

      t.timestamps
    end

    add_index :pg_sql_triggers_audit_log, :trigger_name
    add_index :pg_sql_triggers_audit_log, :operation
    add_index :pg_sql_triggers_audit_log, :status
    add_index :pg_sql_triggers_audit_log, :environment
    add_index :pg_sql_triggers_audit_log, :created_at
    add_index :pg_sql_triggers_audit_log, %i[trigger_name created_at]
  end
end
