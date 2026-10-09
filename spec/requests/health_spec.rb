# frozen_string_literal: true

require "rails_helper"

# The probe a deploy gate rolls back on (docs/HANDOFF.md "Stack"): it must
# read the database, signed out, from a client that is no browser.
RSpec.describe "Health", type: :request do
  it "answers ok signed out, to curl, having read the database", :signed_out do
    expect(User).to receive(:exists?).twice.and_call_original
    get health_path, headers: { "User-Agent" => "curl/8.7.1" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("ok")

    get health_path # no user agent at all, as Docker's healthcheck may send
    expect(response).to have_http_status(:ok)
  end

  it "answers 503 when the database doesn't", :signed_out do
    allow(User).to receive(:exists?).and_raise(ActiveRecord::ConnectionNotEstablished)
    get health_path
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to eq("database: ActiveRecord::ConnectionNotEstablished")
  end
end
