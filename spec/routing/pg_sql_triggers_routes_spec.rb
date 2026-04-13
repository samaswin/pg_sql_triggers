# frozen_string_literal: true

require "spec_helper"

# spec_helper does not call infer_spec_type_from_file_location!, so :routing must be explicit for the `routes` DSL.
RSpec.describe "PgSqlTriggers routes", type: :routing do # rubocop:disable RSpecRails/InferredSpecType
  routes { PgSqlTriggers::Engine.routes }

  it { expect(get: "/").to route_to("pg_sql_triggers/dashboard#index") }
  it { expect(get: "/dashboard").to route_to("pg_sql_triggers/dashboard#index") }

  it { expect(get: "/tables").to route_to("pg_sql_triggers/tables#index") }
  it { expect(get: "/tables/42").to route_to("pg_sql_triggers/tables#show", id: "42") }

  it { expect(post: "/migrations/up").to route_to("pg_sql_triggers/migrations#up") }
  it { expect(post: "/migrations/down").to route_to("pg_sql_triggers/migrations#down") }
  it { expect(post: "/migrations/redo").to route_to("pg_sql_triggers/migrations#redo") }

  it { expect(get: "/triggers/1").to route_to("pg_sql_triggers/triggers#show", id: "1") }
  it { expect(post: "/triggers/1/enable").to route_to("pg_sql_triggers/triggers#enable", id: "1") }
  it { expect(post: "/triggers/1/disable").to route_to("pg_sql_triggers/triggers#disable", id: "1") }
  it { expect(post: "/triggers/1/drop").to route_to("pg_sql_triggers/triggers#drop", id: "1") }
  it { expect(post: "/triggers/1/re_execute").to route_to("pg_sql_triggers/triggers#re_execute", id: "1") }

  it { expect(get: "/audit_logs").to route_to("pg_sql_triggers/audit_logs#index") }
end
