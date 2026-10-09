# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "The studio: generating and picking", type: :request do
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  let(:project) { make_project }
  let(:goblin) { make_subject(project, "Creature", "Goblin") }
  let(:comfy) { FakeComfy.new }

  def generate(subject = goblin, count: 2, notes: "a rusty knife", loras: { "0" => { "name" => "goblin.safetensors", "strength" => "0.6" } }, **params)
    post subject_batches_path(subject), params: { count: count, draft: "0", subject: { notes: notes, loras: loras } }.merge(params)
    subject.batches.order(:id).last
  end

  it "only offers Generate while ComfyUI answers" do
    allow(Comfy).to receive(:capabilities).and_return(Comfy::Capabilities.unreachable)
    get subject_path(goblin)
    expect(page.at("input[value=Generate]").key?("disabled")).to be(true)
    expect(response.body).to include("Nothing can be generated")

    allow(Comfy).to receive(:capabilities).and_return(FakeComfy.capabilities)
    get subject_path(goblin)
    expect(page.at("input[value=Generate]").key?("disabled")).to be(false)
  end

  it "shows the layers and the composed recipe, with the workflow it would build" do
    project.update!(style: "16-bit pixel art")
    get subject_path(goblin)
    expect(response.body).to include("The recipe, in layers", "16-bit pixel art", goblin.kind.prompt)
    expect(response.body).to include("UNETLoader → CLIPLoader")
    expect(page.at("turbo-cable-stream-source")).to be_present
    expect(page.at("turbo-frame#batches")).to be_present
  end

  it "serves the batches alone for their frame to reload, and tells watchers to reload it as candidates land" do
    get subject_panel_path(goblin)
    expect(response.body).to start_with("<turbo-frame ")
    expect(page.at("body").element_children.map(&:name)).to eq([ "turbo-frame" ]) # not a whole page

    batch = generate
    streams = capture_turbo_stream_broadcasts([ goblin, :studio ]) { batch.update!(status: "running") }
    expect(streams.map { |s| [ s["action"], s["target"] ] }).to eq([ %w[reload_frame batches] ])
  end

  it "saves the subject's own layer, then queues a batch of candidates" do
    expect { generate }.to have_enqueued_job(BatchJob)
    expect(response).to redirect_to(subject_path(goblin, anchor: "batches"))
    goblin.reload
    expect(goblin.notes).to eq("a rusty knife")
    expect(goblin.loras).to eq([ { "name" => "goblin.safetensors", "strength" => 0.6, "on" => true } ])
    batch = goblin.batch_for(nil)
    expect(batch.candidates.size).to eq(2)
    expect(batch.recipe["positive"]).to include("Goblin, a rusty knife")
    expect(batch.recipe["loras"]).to eq([ { "name" => "goblin.safetensors", "strength" => 0.6, "on" => true } ])
  end

  it "shows candidates as they land, and picking one makes it the subject's pick with its seed and recipe" do
    batch = finish(generate, comfy)
    get subject_path(goblin)
    expect(response.body).to include("Candidates for Goblin", "Use this", "Seed #{batch.candidates.first.seed}", "43s")

    winner = batch.candidates.last
    post candidate_pick_path(winner)
    expect(response).to redirect_to(subject_path(goblin, anchor: "picks"))
    pick = goblin.reload.pick_for(nil)
    expect(pick.file).to be_attached
    expect(pick.file.filename.to_s).to eq("goblin-#{winner.seed}.png")
    expect(pick).to have_attributes(seed: winner.seed, prompt: batch.recipe["positive"], recipe: batch.recipe, run_seconds: 42.5)
    expect(Batch.exists?(batch.id)).to be(false)

    follow_redirect!
    expect(response.body).to include("Goblin has a new pick (seed #{winner.seed})", "Download", "Sidecar")

    # Picking again makes the new one current; the first stays in the history.
    again = finish(generate(count: 1), comfy).candidates.sole
    post candidate_pick_path(again)
    expect(goblin.picks.count).to eq(2)
    expect(goblin.pick_for(nil).seed).to eq(again.seed)
    expect(goblin.pick_for(nil).user).to eq(@user)

    delete pick_path(goblin.pick_for(nil))
    expect(goblin.reload.pick_for(nil)).to eq(pick) # the one before takes its place
    delete pick_path(pick)
    expect(goblin.picks.reload).to be_empty
  end

  it "replaces the previous batch when generating again, and can discard one" do
    first = generate
    generate
    expect(Batch.exists?(first.id)).to be(false)

    delete subject_batch_path(goblin, goblin.batch_for(nil))
    expect(goblin.batch_for(nil)).to be_nil
  end

  it "won't pick a candidate that isn't finished" do
    batch = generate
    post candidate_pick_path(batch.candidates.first)
    expect(flash[:alert]).to eq("That candidate has nothing to pick yet")
    expect(goblin.picks).to be_empty
  end

  it "generates a variant with its words last, starting from the subject's own pick's seed, and every variant at once" do
    cid = make_subject(project, "Portrait", "Cid", notes: "white beard")
    base = finish(generate(cid, notes: "white beard", loras: {}), comfy)
    post candidate_pick_path(base.candidates.last)
    seed = cid.pick_for(nil).seed

    happy = cid.variants.find_by!(name: "happy")
    batch = generate(cid, notes: "white beard", loras: {}, variant_id: happy.id)
    expect(batch.variant).to eq(happy)
    expect(batch.recipe["positive"]).to end_with("Cid, white beard, smiling happily")
    expect(batch.candidates.first.seed).to eq(seed)
    expect(batch.candidates.second.seed).not_to eq(seed)

    get subject_path(cid)
    expect(response.body).to include("Candidates for Cid, happy")

    finish(batch, comfy)
    post candidate_pick_path(batch.candidates.first)
    expect(cid.pick_for(happy).file.filename.to_s).to eq("cid-happy-#{seed}.png")
    expect(cid.pick_for(nil).seed).to eq(seed) # the subject's own pick stays

    post subject_batches_path(cid), params: { every: "1", count: 1, draft: "0" }
    expect(cid.batches.reload.map(&:variant).compact.map(&:name)).to match_array(cid.variants.map(&:name))
  end

  it "keeps batches to their own subject" do
    batch = generate
    other = make_subject(project, "Creature", "Orc")
    delete subject_batch_path(other, batch)
    expect(response).to have_http_status(:not_found)
    post subject_batches_path(goblin), params: { variant_id: make_subject(project, "Portrait", "Cid").variants.first.id }
    expect(response).to have_http_status(:not_found)
  end

  it "picks models and LoRAs from what ComfyUI has, models grouped by family, keeping a name it no longer has" do
    allow(Comfy).to receive(:capabilities).and_return(FakeComfy.capabilities(
      checkpoints: [ "ponyDiffusionV6XL.safetensors", "sd_xl_base_1.0.safetensors" ],
      diffusion_models: [ "anima-preview.safetensors", "krea2_turbo_bf16.safetensors" ],
      loras: [ "ink.safetensors", "SDXL/pony_sprites.safetensors" ]
    ))
    project.update!(model: "retired.safetensors")
    get edit_project_path(project)
    picker = page.at_css("select#project_model")
    groups = picker.css("optgroup").to_h { |g| [ g["label"], g.css("option").map(&:text) ] }
    expect(groups).to eq("Anima" => [ "anima-preview.safetensors" ], "Krea 2 Turbo" => [ "krea2_turbo_bf16.safetensors" ],
                         "Pony" => [ "ponyDiffusionV6XL.safetensors" ], "SDXL" => [ "sd_xl_base_1.0.safetensors" ],
                         "Not on ComfyUI" => [ "retired.safetensors" ])
    expect(picker.at_css("option[selected]")["value"]).to eq("retired.safetensors")
    expect(picker.at_css("option").text).to eq("Inherit: #{Comfy.config[:model]}")

    loras = page.at_css("select#project_loras_0_name").css("optgroup").to_h { |g| [ g["label"], g.css("option").map(&:text) ] }
    expect(loras).to eq("LoRAs" => [ "ink.safetensors" ], "SDXL" => [ "SDXL/pony_sprites.safetensors" ])

    get subject_path(goblin)
    expect(page.at_css("select#subject_model option[selected]")).to be_nil # inherits

    allow(Comfy).to receive(:capabilities).and_return(Comfy::Capabilities.unreachable)
    get edit_project_path(project)
    expect(page.at_css("input#project_model")["value"]).to eq("retired.safetensors")
  end
end
