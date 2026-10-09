# frozen_string_literal: true

require "rails_helper"

# Overnight (docs/HANDOFF.md "Overnight"): batches and training queued for
# the night window, and what the night made, waiting for review.
RSpec.describe "Overnight", type: :request do
  include ActiveJob::TestHelper

  let(:project) { make_project }
  let(:cid) { make_subject(project, "Portrait", "Cid") }
  let(:comfy) { FakeComfy.new }

  it "queues a batch for tonight from the studio: full quality, frozen now, and nothing replaced either way" do
    post subject_batches_path(cid), params: { count: 2, draft: "0" }
    daytime = cid.batch_for(nil)

    expect { post subject_batches_path(cid), params: { count: 6, draft: "1", tonight: "1" } }.not_to have_enqueued_job(BatchJob)
    expect(flash[:notice]).to include("Queued for tonight")
    night = cid.batches.find_by!(night: true)
    expect(night).to have_attributes(status: "scheduled", draft?: false)
    expect(night.candidates.size).to eq(6)
    expect(Batch.exists?(daytime.id)).to be(true) # tonight's replaces nothing

    post subject_batches_path(cid), params: { count: 1, draft: "0" } # a daytime Generate replaces the daytime batch only
    expect(Batch.exists?(daytime.id)).to be(false)
    expect(Batch.exists?(night.id)).to be(true)

    get subject_path(cid)
    expect(page.at("##{ActionView::RecordIdentifier.dom_id(night)}").text).to include("Overnight:", "Queued for tonight", "Not tonight")
  end

  it "queues every variant for tonight, one batch each" do
    post subject_batches_path(cid), params: { count: 1, tonight: "every" }
    expect(cid.batches.where(night: true, status: "scheduled").count).to eq(cid.variants.count)
  end

  it "shows tonight's queue, takes things off it, and shows what the night made for review" do
    post subject_batches_path(cid), params: { count: 1, tonight: "1" }
    queued = cid.batches.sole
    get night_path
    expect(page.at("#tonight").text).to include("Cid", "1 candidate", "Not tonight")
    expect(page.at("nav").text).to include("Overnight 1")

    # The night shift lets it go, ComfyUI makes it, and it waits for the morning.
    travel_to(Time.utc(2026, 10, 10, 2, 0)) { NightShift.tick!(client: comfy) }
    finish(queued.reload, comfy)
    get night_path
    expect(page.at("#tonight").text).to include("Nothing yet")
    expect(page.at("#made").text).to include(project.name, "Use this", "Seed #{queued.candidates.first.seed}")

    post candidate_pick_path(queued.candidates.first)
    expect(cid.pick_for(nil)).to be_present
    get night_path
    expect(page.at("#made").text).to include("Nothing waiting for review")

    post subject_batches_path(cid), params: { count: 1, tonight: "1" }
    delete subject_batch_path(cid, cid.batches.find_by!(status: "scheduled"))
    expect(cid.batches.where(status: "scheduled")).to be_empty
  end

  it "schedules a training run for tonight, or not after all" do
    entry = project.entries.create!(name: "Cid")
    cid.update!(entry: entry)
    post subject_batches_path(cid), params: { count: 1, draft: "0" }
    post candidate_pick_path(finish(cid.batch_for(nil), comfy).candidates.sole)
    pick = cid.pick_for(nil)

    post entry_trainings_path(entry), params: { train: "tonight", model: "anima-preview.safetensors",
                                                items: { pick.id.to_s => { use: "1", caption: "a portrait" } } }
    run = entry.trainings.sole
    expect(run.status).to eq("scheduled")
    expect(flash[:notice]).to include("will train tonight")
    get night_path
    expect(page.at("#tonight").text).to include("Train Cid v1", "1 picture")

    delete training_run_path(run)
    expect(run.reload.status).to eq("set")
    post training_run_path(run, tonight: 1)
    expect(run.reload.status).to eq("scheduled")
    delete training_path(run)
    expect(flash[:alert]).to include("queued for tonight")
  end

  it "sets the window on the Settings page, refusing what isn't a time or a zone" do
    patch settings_path, params: { site_setting: { night_start: "22:30", night_end: "06:00", night_zone: "America/Los_Angeles" } }
    expect(NightShift.window.label).to eq("22:30 to 06:00, America/Los_Angeles")

    patch settings_path, params: { site_setting: { night_start: "25:00", night_zone: "Mars/Olympus" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be a time like 23:00", "isn&#39;t a time zone")
  end
end
