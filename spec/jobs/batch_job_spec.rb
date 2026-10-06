# frozen_string_literal: true

require "rails_helper"

RSpec.describe BatchJob, type: :job do
  include ActiveJob::TestHelper

  let(:goblin) { make_subject(make_project, "Creature", "Goblin") }
  let(:comfy) { FakeComfy.new }

  def run(batch) = described_class.new.perform(batch.reload, client: comfy)

  it "submits one prompt per candidate, each with its own seed, then collects the images as they land" do
    batch = Batch.start!(goblin, count: 3)
    seeds = batch.candidates.map(&:seed)
    expect(seeds.uniq.size).to eq(3)

    run(batch)
    expect(comfy.submitted.map { |g| g.values.find { |n| n["class_type"] == "KSampler" }["inputs"]["seed"] }).to eq(seeds)
    # The goblin's kind loses its background, so it's rendered on the cut-out's ground, not white (Cutout.on_ground).
    expect(comfy.submitted.first.values.find { |n| n["class_type"] == "CLIPTextEncode" }["inputs"]["text"]).to eq(Cutout.on_ground(goblin.recipe)["positive"])
    expect(batch.reload.status).to eq("running")
    expect(enqueued_jobs.count { |j| j["job_class"] == "BatchJob" }).to be >= 2 # the start, then a check-back

    comfy.finish!("prompt-1")
    run(batch)
    expect(batch.candidates.map { |c| [ c.status, c.file.attached? ] }).to eq([ [ "done", true ], [ "running", false ], [ "running", false ] ])

    comfy.finish!("prompt-2", "prompt-3")
    run(batch)
    expect(batch.reload.status).to eq("done")
    expect(batch.candidates.map(&:transparent)).to all(be(true)) # the goblin's kind removes its background, and the images have alpha
    expect(comfy.submitted.size).to eq(3) # nothing resubmitted
  end

  it "keeps the good candidates when one fails, and fails the batch when all do" do
    batch = Batch.start!(goblin, count: 2)
    run(batch)
    comfy.finish!("prompt-1")
    comfy.fail!("prompt-2", "KSampler: out of memory")
    run(batch)
    expect(batch.reload.status).to eq("done")
    expect(batch.candidates.last).to have_attributes(status: "failed", error: "KSampler: out of memory")

    other = Batch.start!(goblin, count: 1)
    run(other)
    comfy.fail!("prompt-3", "LoraLoader: missing file")
    run(other)
    expect(other.reload).to have_attributes(status: "failed", error: "LoraLoader: missing file")
  end

  it "fails the batch with ComfyUI's reason when ComfyUI refuses it" do
    batch = Batch.start!(goblin, count: 2)
    allow(comfy).to receive(:submit).and_raise(Comfy::Error, "CheckpointLoaderSimple: model not found")
    run(batch)
    expect(batch.reload).to have_attributes(status: "failed", error: "CheckpointLoaderSimple: model not found")
    expect(batch.candidates.map(&:status).uniq).to eq([ "failed" ])
  end

  describe "when ComfyUI can't be reached" do
    let(:down) { "ComfyUI isn't reachable at http://comfy.test (OpenTimeout: execution expired)" }

    # Through Active Job, so its retrying runs (the job finds ComfyUI itself).
    def run_as_queued(batch) = described_class.perform_now(batch.reload)

    before { allow(Comfy).to receive(:client).and_return(comfy) }

    it "waits and tries again later, less often the longer it's down, then carries on when it's back" do
      batch = Batch.start!(goblin, count: 2)
      clear_enqueued_jobs
      allow(comfy).to receive(:submit).and_raise(Comfy::Unreachable, down)
      expect { run_as_queued(batch) }.to have_enqueued_job(described_class).with(batch).at(a_value_within(1.second).of(30.seconds.from_now))
      expect(batch.reload).to have_attributes(status: "waiting", error: down)
      expect(batch.candidates.map(&:status).uniq).to eq([ "queued" ]) # nothing lost

      expect((1..7).map { |n| ApplicationJob.service_retry_wait(n) }).to eq([ 30, 60, 120, 240, 480, 600, 600 ].map(&:seconds))

      allow(comfy).to receive(:submit).and_call_original
      run_as_queued(batch)
      expect(batch.reload).to have_attributes(status: "running", error: nil)
      expect(comfy.submitted.size).to eq(2)
      comfy.finish!("prompt-1", "prompt-2")
      run(batch)
      expect(batch.reload.status).to eq("done")
    end

    it "keeps what's rendering when ComfyUI drops out mid-batch" do
      batch = Batch.start!(goblin, count: 2)
      run(batch)
      allow(comfy).to receive(:result).and_raise(Comfy::Unreachable, down)
      run_as_queued(batch)
      expect(batch.reload.status).to eq("waiting")
      expect(batch.candidates.map(&:status).uniq).to eq([ "running" ])

      allow(comfy).to receive(:result).and_call_original
      comfy.finish!("prompt-1", "prompt-2")
      run(batch)
      expect(batch.reload.status).to eq("done")
      expect(comfy.submitted.size).to eq(2) # nothing resubmitted
    end

    it "gives up after a day of trying" do
      batch = Batch.start!(goblin, count: 1)
      allow(comfy).to receive(:submit).and_raise(Comfy::Unreachable, down)
      job = described_class.new(batch)
      job.exception_executions = { "[Remote::Unreachable]" => ApplicationJob::SERVICE_RETRY_ATTEMPTS - 1 } # this is the last try
      job.perform_now
      expect(batch.reload.status).to eq("failed")
      expect(batch.error).to include("Tried for a day")
    end
  end

  it "gives up after the timeout" do
    batch = Batch.start!(goblin, count: 1)
    run(batch)
    travel(Comfy.config[:timeout].to_i.seconds + 1) { run(batch) }
    expect(batch.reload.status).to eq("failed")
    expect(batch.error).to match(/didn't finish/)
  end

  it "does nothing for a batch that was discarded" do
    batch = Batch.start!(goblin, count: 1) # enqueues the job
    batch.destroy!
    expect { perform_enqueued_jobs(only: described_class) }.not_to raise_error
  end
end
