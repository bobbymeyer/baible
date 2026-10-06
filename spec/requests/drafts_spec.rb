# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Drafts first, then made properly", type: :request do
  include ActiveJob::TestHelper

  let(:goblin) { make_subject(make_project, "Creature", "Goblin") }
  let(:comfy) { FakeComfy.new }

  def run(batch) = BatchJob.new.perform(batch.reload, client: comfy)
  def node(graph, type) = graph.values.find { |n| n["class_type"] == type }

  it "drafts small and quick, then makes the chosen one properly from the draft" do
    post subject_batches_path(goblin), params: { count: 2, draft: "1", transparent: "1" }
    drafts = goblin.batch_for(nil)
    expect(drafts).to be_draft
    expect(drafts.recipe).to include("steps" => 16, "width" => 512, "height" => 512, "transparent" => true)
    expect(drafts.recipe["full"]).to include("width" => 1024, "height" => 1024, "transparent" => true)

    run(drafts)
    graph = comfy.submitted.first
    expect(node(graph, "KSampler")["inputs"]).to include("steps" => 16, "denoise" => 1)
    expect(node(graph, "EmptyLatentImage")["inputs"]).to include("width" => 512, "height" => 512)
    comfy.finish!("prompt-1", "prompt-2")
    run(drafts)
    expect(node(graph, "BiRefNetRMBG")).to be_present # a draft is cut out too: it can be used as it is
    expect(drafts.candidates.map(&:transparent)).to all(be(true))
    chosen = drafts.candidates.reload.second
    expect(chosen.run_seconds).to eq(42.5)

    get subject_path(goblin)
    expect(response.body).to include("Drafts for Goblin", "Make this one properly", "Use the draft", "43s")

    post candidate_refinement_path(chosen)
    refinement = goblin.batch_for(nil)
    expect(refinement.recipe).to include("width" => 1024, "height" => 1024, "transparent" => true, "denoise" => 0.6)
    expect(refinement.candidates.sole.seed).to eq(chosen.seed)
    expect(refinement.drafts).to eq(drafts)

    run(refinement)
    expect(comfy.uploads.sole.first).to eq("baible-draft-#{chosen.id}-#{chosen.seed}.png")
    expect(Cutout.png_alpha?(comfy.uploads.sole.last)).to be(false) # redrawn from the render on its ground, not the cut-out
    graph = comfy.submitted.last
    expect(node(graph, "LoadImage")["inputs"]).to eq("image" => "baible-draft-#{chosen.id}-#{chosen.seed}.png")
    expect(node(graph, "ImageScale")["inputs"]).to include("width" => 1024, "height" => 1024)
    expect(node(graph, "KSampler")["inputs"]).to include("steps" => 30, "denoise" => 0.6, "seed" => chosen.seed)
    expect(node(graph, "EmptyLatentImage")).to be_nil

    get subject_path(goblin)
    body = response.body
    expect(body).to include("Made properly for Goblin", "Drafts for Goblin")
    expect(body.index("Made properly for Goblin")).to be < body.index("Drafts for Goblin") # the drafts it came from, under it

    comfy.finish!("prompt-3")
    run(refinement)
    expect(node(comfy.submitted.last, "BiRefNetRMBG")).to be_present
    expect(refinement.candidates.sole.transparent).to be(true)
    post candidate_pick_path(refinement.candidates.sole)
    expect(goblin.pick_for(nil).file).to be_attached
    expect(goblin.batches.reload).to be_empty # drafts and all
  end

  it "only makes a finished draft properly" do
    post subject_batches_path(goblin), params: { count: 1, draft: "0" }
    batch = finish(goblin.batch_for(nil), comfy)
    post candidate_refinement_path(batch.candidates.sole)
    expect(flash[:alert]).to eq("Only a draft can be made properly")
  end
end
