# frozen_string_literal: true

# Where the morning summary goes (docs/HANDOFF.md "The morning summary"):
# MORNING_WEBHOOK_URL, environment only, since a webhook's address is often
# its secret (a Slack or Discord hook, an ntfy topic). MORNING_WEBHOOK_FORMAT
# is "json" (the default: an object with a "text" field, which Slack,
# Mattermost and n8n read, and the summary's figures beside it) or "text"
# (the summary as plain text, which ntfy shows as is). MORNING_WEBHOOK_HEADERS
# adds headers, as JSON (a bearer token, ntfy's Title).
module Webhook
  class Error < StandardError; end
  class Unreachable < Error; include Remote::Unreachable; end

  module_function

  def url = ENV.fetch("MORNING_WEBHOOK_URL", "").strip.presence

  def enabled? = url.present?

  def format = ENV.fetch("MORNING_WEBHOOK_FORMAT", "json").strip.downcase == "text" ? "text" : "json"

  def deliver(text, payload, http: nil)
    connection = Remote::Connection.new(service: Webhook, name: "The morning webhook", url: url,
                                        headers: ENV.fetch("MORNING_WEBHOOK_HEADERS", "{}"), headers_setting: "MORNING_WEBHOOK_HEADERS",
                                        timeout: 30, http: http)
    if format == "text"
      connection.post_body("", text, "text/plain; charset=utf-8")
    else
      connection.post_json("", payload.merge("text" => text))
    end
    true
  end
end
