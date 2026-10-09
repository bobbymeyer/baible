# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightShift do
  include ActiveJob::TestHelper

  let(:la) { ActiveSupport::TimeZone["America/Los_Angeles"] }
  let(:window) { NightShift::Window.new(start: "23:00", finish: "07:00", zone: la) }

  describe NightShift::Window do
    it "is open across midnight, in its own time zone" do
      expect(window.open?(la.parse("2026-10-09 23:00"))).to be(true)
      expect(window.open?(la.parse("2026-10-10 03:30"))).to be(true)
      expect(window.open?(la.parse("2026-10-10 07:00"))).to be(false)
      expect(window.open?(la.parse("2026-10-10 14:00"))).to be(false)
      expect(window.open?(Time.utc(2026, 10, 10, 10, 0))).to be(true) # 03:00 in Los Angeles
    end

    it "is open within a day when it doesn't cross midnight, and knows when it next opens" do
      day = NightShift::Window.new(start: "01:00", finish: "05:00", zone: la)
      expect(day.open?(la.parse("2026-10-10 02:00"))).to be(true)
      expect(day.open?(la.parse("2026-10-10 05:30"))).to be(false)
      expect(window.opens_at(la.parse("2026-10-10 14:00"))).to eq(la.parse("2026-10-10 23:00"))
      expect(window.opens_at(la.parse("2026-10-10 23:30"))).to eq(la.parse("2026-10-10 23:30"))
    end
  end

  describe ".tick!" do
    let(:project) { make_project }
    let(:goblin) { make_subject(project, "Creature", "Goblin") }
    let(:comfy) { FakeComfy.new }
    let(:night) { Time.utc(2026, 10, 10, 2, 0) } # inside the default 23:00-07:00 UTC window
    let(:noon) { Time.utc(2026, 10, 10, 12, 0) }

    def tick(at: night) = NightShift.tick!(client: comfy, at: at)

    it "lets nothing go outside the window, or when nothing is queued" do
      expect(tick).to eq(:nothing_queued)
      Batch.start!(goblin, count: 2, tonight: true)
      expect(tick(at: noon)).to eq(:closed)
    end

    it "lets one thing go at a time, generations before training, oldest first, and only while ComfyUI is idle" do
      cid = project.entries.create!(name: "Cid")
      portrait = make_subject(project, "Portrait", "Cid", entry: cid)
      pick = Pick.new(subject: portrait, seed: 1, current: true, recipe: {}).tap { |p| p.file.attach(io: StringIO.new(FakeComfy.png), filename: "c.png", content_type: "image/png") }
      pick.save!
      run = Training.start!(cid, [ { pick: pick, caption: "a portrait" } ], trigger: "cidx", model: "anima-preview.safetensors",
                            settings: {}, user: nil, train: :tonight)
      first = Batch.start!(goblin, count: 1, tonight: true)
      second = Batch.start!(goblin, count: 1, tonight: true)
      expect(enqueued_jobs.map { |job| job["job_class"] }).not_to include("BatchJob", "TrainingJob")

      comfy.queue_size = 1 # someone else's prompt
      expect(tick).to eq(:comfy_busy)
      comfy.queue_size = 0

      expect { expect(tick).to eq(first) }.to have_enqueued_job(BatchJob).with(first)
      expect(first.reload).to have_attributes(status: "queued", released_at: be_present)
      expect(tick).to eq(:busy) # the first is still with ComfyUI

      first.update!(status: "done")
      expect(tick).to eq(second)
      second.update!(status: "done")
      expect { expect(tick).to eq(run) }.to have_enqueued_job(TrainingJob).with(run)
      expect(run.reload.status).to eq("queued")
    end

    it "waits, quietly, when ComfyUI can't be asked" do
      Batch.start!(goblin, count: 1, tonight: true)
      allow(comfy).to receive(:queue_size).and_raise(Comfy::Unreachable, "down")
      expect(tick).to eq(:comfy_unreachable)
      expect(Batch.sole.status).to eq("scheduled")
    end

    it "counts a released batch's time with ComfyUI from its release, not from when it was queued" do
      batch = Batch.start!(goblin, count: 1, tonight: true)
      travel(ComfyRun.timeout + 1.hour) do
        batch.release!
        expect(batch).not_to be_timed_out
      end
    end
  end
end
