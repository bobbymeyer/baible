# frozen_string_literal: true

# A health check that touches the database, for a container healthcheck
# and a deploy gate to roll back on (docs/HANDOFF.md "Stack"). /up answers
# the moment Rails boots, and the signed-out redirect never reads SQLite
# (no cookie, no session lookup), so neither can tell a working app from
# one whose database is gone. This reads the users table, signed out, and
# answers 200 "ok" or 503 with the reason.
class HealthController < ApplicationController
  allow_unauthenticated_access

  def show
    User.exists?
    render plain: "ok"
  rescue ActiveRecord::ActiveRecordError => e
    render plain: "database: #{e.class.name}", status: :service_unavailable
  end
end
