# frozen_string_literal: true

module PgSqlTriggers
  class Migration < ActiveRecord::Migration[6.1]
    # Base class for trigger migrations
    # Similar to ActiveRecord::Migration but for trigger-specific migrations

    # rubocop:disable Rails/Delegate
    # delegate doesn't work here due to argument forwarding issues in this context
    def execute(sql)
      connection.execute(sql)
    end
    # rubocop:enable Rails/Delegate
  end
end
