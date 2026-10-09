# frozen_string_literal: true

require "rails_helper"
require "rubygems/package"

# The LoRA loop (docs/HANDOFF.md "The LoRA loop"): an entry's picks, chosen
# and captioned, train a LoRA in ComfyUI, and the entry then makes its
# assets with it.
RSpec.describe "Training a LoRA on an entry", type: :request do
  include ActiveJob::TestHelper

  let(:project) { make_project(style: "ink wash") }
  let(:cid) { project.entries.create!(name: "Cid", look: "eyepatch over the left eye") }
  let(:portrait) { make_subject(project, "Portrait", "Cid", entry: cid, notes: "white beard") }
  let(:sprite) { make_subject(project, "Character sprite", "Cid", entry: cid) }
  let(:comfy) { FakeComfy.new }

  before { allow(Comfy).to receive(:client).and_return(comfy) }

  def pick_one(subject, variant: nil)
    post subject_batches_path(subject), params: { count: 1, draft: "0", variant_id: variant&.id }
    post candidate_pick_path(finish(subject.batch_for(variant), comfy).candidates.sole)
    subject.target_picks(variant).first
  end

  def train(picks, train: "1", **params)
    items = picks.to_h { |pick| [ pick.id.to_s, { use: "1", caption: Training.caption_for(pick) } ] }
    post entry_trainings_path(cid), params: { trigger: "cidx", model: "anima-preview.safetensors", train: train, items: items, **params }
    cid.trainings.first
  end

  it "offers every image pick of the entry, captioned from its recipe without the look, the standing ones ticked" do
    face = pick_one(portrait)
    older = face
    face = pick_one(portrait) # the first stays in the history
    body = pick_one(sprite)

    get new_entry_training_path(cid)
    expect(page.css(".training-set__item").size).to eq(3)
    expect(page.at("#use_#{face.id}")["checked"]).to be_present
    expect(page.at("#use_#{older.id}")["checked"]).to be_nil
    expect(page.at("#use_#{body.id}")["checked"]).to be_present
    caption = page.at("#caption_#{face.id}").text.strip
    expect(caption).to start_with("ink wash, a head and shoulders portrait").and include("Cid, white beard")
    expect(caption).not_to include("eyepatch", "masterpiece")
    expect(page.at("input#trigger")["value"]).to eq("cid")
  end

  it "trains in ComfyUI: uploads the set, queues the graph, and the entry then uses the LoRA" do
    face = pick_one(portrait)
    body = pick_one(sprite)
    run = nil
    expect { run = train([ face, body ], settings: { steps: "800" }) }.to have_enqueued_job(TrainingJob)
    expect(response).to redirect_to(entry_path(cid, anchor: "lora"))
    expect(run).to have_attributes(version: 1, status: "queued", trigger: "cidx", family: "anima", user: @user)
    expect(run.settings).to eq("steps" => 800, "rank" => 16, "learning_rate" => 0.0001, "batch_size" => 1)
    expect(run.items.map { |item| item["caption"] }.first).to start_with("cidx, ink wash")
    expect(cid.reload.trigger).to eq("cidx")

    TrainingJob.new.perform(run, client: comfy)
    expect(comfy.uploads.map(&:first)).to eq(%w[001.png 001.txt 002.png 002.txt].map { |f| "baible/train/the-drowned-coast-cid-v1/#{f}" })
    expect(comfy.uploads[1].last).to start_with("cidx, ink wash")
    graph = comfy.submitted.last
    expect(Comfy::Workflow.outline(graph)).to eq("UNETLoader → CLIPLoader → VAELoader → LoadImageTextDataSetFromFolder → MakeTrainingDataset → " \
                                                 "ResolutionBucket → TrainLoraNode → SaveLoRA")
    trainer = graph.values.find { |node| node["class_type"] == "TrainLoraNode" }["inputs"]
    expect(trainer).to include("steps" => 800, "rank" => 16, "bucket_mode" => true, "existing_lora" => "[None]")
    expect(graph.values.find { |node| node["class_type"] == "SaveLoRA" }["inputs"]["prefix"]).to eq("loras/baible/the-drowned-coast-cid-v1")
    expect(run.reload).to have_attributes(status: "running", workflow: start_with("UNETLoader"))

    # Still training: nothing yet. Then ComfyUI lists the LoRA it saved.
    TrainingJob.new.perform(run, client: comfy)
    expect(run.reload.status).to eq("running")
    comfy.add_lora("baible/the-drowned-coast-cid-v1_00001_.safetensors")
    comfy.finish!(run.comfy_prompt_id)
    TrainingJob.new.perform(run, client: comfy)
    expect(run.reload).to have_attributes(status: "done", lora: "baible/the-drowned-coast-cid-v1_00001_.safetensors")
    expect(cid.reload.training).to eq(run)

    # Its images now carry the trigger and the LoRA; the look stays.
    recipe = portrait.reload.recipe
    expect(recipe["parts"]["entry"]).to eq("cidx, eyepatch over the left eye")
    expect(recipe["loras"]).to include({ "name" => run.lora, "strength" => 1.0, "on" => true })

    # A model of another family keeps it, switched off, and no trigger.
    portrait.update!(model: "ponyDiffusionV6XL.safetensors")
    recipe = portrait.reload.recipe
    expect(recipe["loras"]).to include({ "name" => run.lora, "strength" => 1.0, "on" => false })
    expect(recipe["parts"]["entry"]).to eq("eyepatch over the left eye")

    get entry_path(cid)
    expect(page.at("#trainings").text).to include("Uses Cid v1", "Trained", "Stop using it")
  end

  it "keeps a set without training it, downloads it as a kohya tar, and trains it later" do
    face = pick_one(portrait)
    run = nil
    expect { run = train([ face ], train: "0") }.not_to have_enqueued_job(TrainingJob)
    expect(run.status).to eq("set")

    get training_set_path(run)
    expect(response.headers["Content-Disposition"]).to include("the-drowned-coast-cid-v1.tar")
    files = {}
    Gem::Package::TarReader.new(StringIO.new(response.body)) { |tar| tar.each { |entry| files[entry.full_name] = entry.read } }
    expect(files.keys).to eq(%w[the-drowned-coast-cid-v1/1_cidx/001.png the-drowned-coast-cid-v1/1_cidx/001.txt])
    expect(files.values.last).to start_with("cidx, ink wash")
    expect(Cutout.png_alpha?(files.values.first)).to be(false) # flattened on white

    expect { post training_run_path(run) }.to have_enqueued_job(TrainingJob)
    expect(run.reload.status).to eq("queued")
  end

  it "fails a run with ComfyUI's reason, and it can be tried again" do
    run = train([ pick_one(portrait) ])
    TrainingJob.new.perform(run, client: comfy)
    comfy.fail!(run.reload.comfy_prompt_id, "TrainLoraNode: out of memory")
    TrainingJob.new.perform(run, client: comfy)
    expect(run.reload).to have_attributes(status: "failed", error: "TrainLoraNode: out of memory")
    expect(cid.reload.training).to be_nil

    get entry_path(cid)
    expect(page.at("#trainings").text).to include("Failed", "out of memory")
    expect { post training_run_path(run) }.to have_enqueued_job(TrainingJob)
  end

  it "says what's missing when ComfyUI can't train" do
    comfy = FakeComfy.new(capabilities: FakeComfy.capabilities(nodes: Comfy::Capabilities::NODES - %w[TrainLoraNode SaveLoRA]))
    run = train([ pick_one(portrait) ])
    TrainingJob.new.perform(run, client: comfy)
    expect(run.reload.error).to eq("This ComfyUI can't train a LoRA: it has no TrainLoraNode and SaveLoRA nodes (update ComfyUI)")
  end

  it "won't let a pick a run used go, and takes only the entry's own image picks" do
    face = pick_one(portrait)
    stranger = pick_one(make_subject(project, "Creature", "Wolf"))
    run = train([ face, stranger ], train: "0")
    expect(run.items.map { |item| item["pick_id"] }).to eq([ face.id ])

    delete pick_path(face)
    expect(flash[:alert]).to include("trained a LoRA")
    expect(Pick.exists?(face.id)).to be(true)

    post entry_trainings_path(cid), params: { items: {} }
    expect(flash[:alert]).to eq("Choose at least one picture for the set")
  end

  it "switches the LoRA in use between runs, or off, and deleting the entry takes its runs" do
    face = pick_one(portrait)
    first = train([ face ], train: "0")
    first.update!(status: "done", lora: "baible/a.safetensors")
    second = train([ face ], train: "0")
    second.update!(status: "done", lora: "baible/b.safetensors")
    expect(second.version).to eq(2)

    post training_use_path(first)
    expect(cid.reload.training).to eq(first)
    delete training_use_path(first)
    expect(cid.reload.training).to be_nil
    post training_use_path(second)
    delete training_path(second)
    expect(cid.reload.training).to be_nil

    delete entry_path(cid)
    expect(Training.count).to eq(0)
  end
end
