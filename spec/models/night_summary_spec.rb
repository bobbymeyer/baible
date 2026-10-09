# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightSummary do
  include ActiveJob::TestHelper

  let(:project) { make_project }
  let(:goblin) { make_subject(project, "Creature", "Goblin") }
  let(:comfy) { FakeComfy.new }
  let(:night) { Time.utc(2026, 10, 10, 2, 0) }
  let(:morning) { Time.utc(2026, 10, 10, 7, 30) }

  it "knows the night that last closed" do
    window = NightShift::Window.new(start: "23:00", finish: "07:00", zone: ActiveSupport::TimeZone["UTC"])
    expect(window.last_night(morning)).to eq([ Time.utc(2026, 10, 9, 23, 0), Time.utc(2026, 10, 10, 7, 0) ])
    expect(window.last_night(night)).to be_nil
  end

  it "is written once, at the first tick after the window closes, from what the night did" do
    batch = Batch.start!(goblin, count: 2, tonight: true)
    travel_to(night) { NightShift.tick!(client: comfy) }
    finish(batch.reload, comfy)
    Batch.start!(goblin, variant: nil, count: 1, tonight: true).update!(status: "scheduled") # not reached
    project.standing_orders.create!(action: "fill_gaps", planned_at: night, report: "Queued 1 batch of 2.")

    expect(Webhook).not_to receive(:deliver)
    travel_to(morning) { NightShift.tick!(client: comfy) }
    summary = NightSummary.sole
    expect(summary.text).to eq(<<~TEXT.chomp)
      1 batch made (2 candidates).
      To review in The Drowned Coast: Goblin.
      Not reached, still queued: 1.
      Standing order: Fill the gaps, The Drowned Coast: Queued 1 batch of 2.
    TEXT
    expect(summary.payload["batches"]).to eq("made" => 1, "failed" => 0, "still_running" => 0, "candidates" => 2)

    travel_to(morning + 1.hour) { NightShift.tick!(client: comfy) }
    expect(NightSummary.count).to eq(1)
  end

  it "reports training without a batch line when only training ran, and links the Overnight page" do
    stub_const("ENV", ENV.to_h.merge("APP_URL" => "https://baible.example/"))
    entry = project.entries.create!(name: "Cid")
    entry.trainings.new(version: 1, trigger: "cidx", model: "m", family: "sdxl", items: [ { "pick_id" => 1 } ], status: "failed",
                        error: "TrainLoraNode: out of memory", updated_at: night).save!(touch: false)
    text = NightSummary.write!(Time.utc(2026, 10, 9, 23), Time.utc(2026, 10, 10, 7)).text
    expect(text.lines.map(&:chomp)).to eq([ "Training Cid v1 failed: TrainLoraNode: out of memory", "https://baible.example/night" ])
  end

  it "is sent to the morning webhook as JSON with a text field, or as plain text, and keeps a failed send's reason" do
    stub_const("ENV", ENV.to_h.merge("MORNING_WEBHOOK_URL" => "https://hooks.example/abc?x=1"))
    http = FakeHttp.new("/abc" => [ 200, "ok" ])
    allow(Webhook).to receive(:deliver).and_wrap_original { |original, text, payload| original.call(text, payload, http: http) }

    summary = NightSummary.write!(Time.utc(2026, 10, 9, 23), Time.utc(2026, 10, 10, 7))
    expect(summary.sent_at).to be_present
    sent = http.requests.sole
    expect(sent.path).to eq("/abc?x=1")
    expect(JSON.parse(sent.body)).to include("text" => "Nothing ran last night.", "title" => "baible: last night (October 10, 2026)")

    stub_const("ENV", ENV.to_h.merge("MORNING_WEBHOOK_URL" => "https://hooks.example/abc", "MORNING_WEBHOOK_FORMAT" => "text"))
    NightSummary.write!(Time.utc(2026, 10, 10, 23), Time.utc(2026, 10, 11, 7))
    expect(http.requests.last.body).to eq("Nothing ran last night.")
    expect(http.requests.last["Content-Type"]).to start_with("text/plain")

    failing = FakeHttp.new("/abc" => [ 500, "nope" ])
    allow(Webhook).to receive(:deliver).and_wrap_original { |original, text, payload| original.call(text, payload, http: failing) }
    later = NightSummary.write!(Time.utc(2026, 10, 11, 23), Time.utc(2026, 10, 12, 7))
    expect(later).to have_attributes(sent_at: nil, error: "The morning webhook answered 500")
  end
end
