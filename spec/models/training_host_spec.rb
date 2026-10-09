# frozen_string_literal: true

require "rails_helper"

# Training on a second ComfyUI, a rented GPU (docs/HANDOFF.md "Training
# hosts"), and the LoRA's way home.
RSpec.describe "Training hosts" do
  include ActiveJob::TestHelper

  let(:project) { make_project }
  let(:cid) { project.entries.create!(name: "Cid") }
  let(:portrait) { make_subject(project, "Portrait", "Cid", entry: cid) }
  let(:remote) { FakeComfy.new }
  let(:lora_dir) { Dir.mktmpdir }

  def configure(host: {}, loras: {})
    allow(Comfy).to receive(:config).and_wrap_original do |original|
      config = original.call
      config.merge(training_host: config.fetch(:training_host, {}).merge(host), trained_loras: config.fetch(:trained_loras, {}).merge(loras))
    end
  end

  def pick
    portrait.picks.update_all(current: false)
    Pick.new(subject: portrait, seed: 7, current: true, recipe: { "parts" => { "subject" => "Cid" } }).tap do |p|
      p.file.attach(io: StringIO.new(FakeComfy.png), filename: "p.png", content_type: "image/png")
      p.save!
    end
  end

  def run_on(host: nil, train: :now)
    Training.start!(cid, [ { pick: pick, caption: "Cid" } ], trigger: "cidx", model: "anima-preview.safetensors", settings: {},
                    user: nil, train: train, host: host)
  end

  after { FileUtils.rm_rf(lora_dir) }

  it "trains on the training host when there is one, starting and stopping the RunPod pod around it" do
    configure(host: { url: "https://pod-8188.proxy.runpod.net", runpod_pod_id: "pod" }, loras: { dir: lora_dir, prefix: "baible" })
    stub_const("ENV", ENV.to_h.merge("RUNPOD_API_KEY" => "key"))
    expect(RunPod).to receive(:start!).once
    expect(RunPod).to receive(:stop!).once

    run = run_on
    expect(run.host).to eq("remote")
    TrainingJob.new.perform(run, client: remote)
    expect(run.reload).to have_attributes(status: "running", host_started_at: be_present)
    expect(remote.uploads.map(&:first)).to include("baible/train/the-drowned-coast-cid-v1/001.png")

    remote.finish!(run.comfy_prompt_id)
    TrainingJob.new.perform(run, client: remote)
    expect(run.reload).to have_attributes(status: "done", lora: "baible/the-drowned-coast-cid-v1.safetensors", host_started_at: nil)
    expect(run.lora_file).to be_attached
    expect(File.binread(File.join(lora_dir, "the-drowned-coast-cid-v1.safetensors"))).to eq(run.lora_file.download)
    expect(cid.reload.training).to eq(run)
  end

  it "waits while a started pod boots, and fails a run RunPod refuses" do
    configure(host: { url: "https://pod-8188.proxy.runpod.net", runpod_pod_id: "pod" })
    stub_const("ENV", ENV.to_h.merge("RUNPOD_API_KEY" => "key"))
    allow(RunPod).to receive(:start!)
    booting = FakeComfy.new(capabilities: Comfy::Capabilities.unreachable("ComfyUI answered 502"))

    run = run_on
    allow(Comfy).to receive(:client_for).with("remote").and_return(booting)
    expect { TrainingJob.perform_now(run) }.to have_enqueued_job(TrainingJob).with(run) # retried, not failed
    expect(run.reload).to have_attributes(status: "waiting", error: include("isn't up yet"))

    other = run_on
    allow(RunPod).to receive(:start!).and_raise(RunPod::Error, "RunPod answered 401")
    allow(RunPod).to receive(:stop!)
    TrainingJob.new.perform(other, client: remote)
    expect(other.reload).to have_attributes(status: "failed", error: "RunPod wouldn't start the pod: RunPod answered 401")
  end

  it "says loudly when the pod wouldn't stop" do
    configure(host: { url: "https://pod-8188.proxy.runpod.net", runpod_pod_id: "pod" })
    stub_const("ENV", ENV.to_h.merge("RUNPOD_API_KEY" => "key"))
    allow(RunPod).to receive(:start!)
    allow(RunPod).to receive(:stop!).and_raise(RunPod::Unreachable, "RunPod isn't reachable")
    run = run_on
    TrainingJob.new.perform(run, client: remote)
    remote.fail!(run.reload.comfy_prompt_id, "TrainLoraNode: out of memory")
    TrainingJob.new.perform(run, client: remote)
    expect(run.reload.status).to eq("failed")
    expect(run.host_note).to eq("RunPod didn't stop pod pod (RunPod isn't reachable): stop it by hand, it's costing money.")
  end

  it "trains here without a training host, and still brings the LoRA into ComfyUI's folder when it can" do
    configure(loras: { dir: lora_dir, prefix: "baible" })
    run = run_on
    expect(run.host).to eq("local")
    local = FakeComfy.new
    TrainingJob.new.perform(run, client: local)
    local.finish!(run.reload.comfy_prompt_id)
    TrainingJob.new.perform(run, client: local)
    expect(run.reload.lora).to eq("baible/the-drowned-coast-cid-v1.safetensors")
    expect(Dir.children(lora_dir)).to eq([ "the-drowned-coast-cid-v1.safetensors" ])
  end

  it "fails a remote run when the training host is gone from the configuration" do
    run = run_on(host: "remote")
    TrainingJob.new.perform(run)
    expect(run.reload).to have_attributes(status: "failed", error: "No training host is set (TRAINING_COMFY_URL)")
  end

  it "lets a remote run go beside local generation, one at a time on the host" do
    configure(host: { url: "https://gpu.example" })
    goblin = make_subject(project, "Creature", "Goblin")
    first = run_on(train: :tonight)
    second = run_on(train: :tonight)
    batch = Batch.start!(goblin, count: 1, tonight: true)
    night = Time.utc(2026, 10, 10, 2, 0)

    NightShift.tick!(client: FakeComfy.new, at: night)
    expect([ first.reload.status, second.reload.status, batch.reload.status ]).to eq(%w[queued scheduled queued])
    NightShift.tick!(client: FakeComfy.new, at: night)
    expect(second.reload.status).to eq("scheduled") # the host is busy with the first
  end
end
