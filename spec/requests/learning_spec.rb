# frozen_string_literal: true

require "rails_helper"

# The Models and workflows page (docs/HANDOFF.md "Unknown models and new
# workflows"): asking the language model, editing what it wrote, trying it
# and accepting it.
RSpec.describe "Models and workflows", type: :request do
  include ActiveJob::TestHelper

  let(:caps) { FakeComfy.capabilities(diffusion_models: [ "anima-preview.safetensors", "mystery-v1.safetensors" ]) }
  let(:comfy) { FakeComfy.new(capabilities: caps) }
  let(:settings) do
    { "text_encoder" => [ "qwen_3_06b" ], "clip_type" => [ "anima" ], "vae" => [ "qwen_image_vae" ], "lora" => "model", "steps" => 28, "cfg" => 4.0,
      "sampler" => [ "euler" ], "scheduler" => [ "simple" ], "negative" => true, "prefix" => "", "negative_prefix" => "",
      "prompt_style" => "prose", "pixels" => [ 786_432, 1_310_720 ], "multiple" => 16 }
  end
  let(:graph) do
    {
      "1" => { "class_type" => "CheckpointLoaderSimple", "inputs" => { "ckpt_name" => "{{model}}" } },
      "2" => { "class_type" => "CLIPTextEncode", "inputs" => { "text" => "{{prompt}}", "clip" => [ "1", 1 ] } },
      "4" => { "class_type" => "EmptyLatentImage", "inputs" => { "width" => "{{width}}", "height" => "{{height}}", "batch_size" => 1 } },
      "5" => { "class_type" => "KSampler", "inputs" => { "model" => [ "1", 0 ], "seed" => "{{seed}}", "steps" => 25, "cfg" => 6.0,
                                                           "sampler_name" => "euler", "scheduler" => "normal", "positive" => [ "2", 0 ],
                                                           "negative" => [ "2", 0 ], "latent_image" => [ "4", 0 ], "denoise" => 1.0 } },
      "6" => { "class_type" => "VAEDecode", "inputs" => { "samples" => [ "5", 0 ], "vae" => [ "1", 2 ] } },
      "7" => { "class_type" => "SaveImage", "inputs" => { "images" => [ "6", 0 ], "filename_prefix" => "{{prefix}}" } }
    }
  end

  before do
    allow(Comfy).to receive_messages(capabilities: caps, client: comfy)
    allow(Llm).to receive(:enabled?).and_return(true)
  end

  it "lists ComfyUI's models with how each runs, and asks about an unknown one" do
    get learning_path
    rows = page.css("#models tbody tr").to_h { |row| [ row.at("code").text, row.text.squish ] }
    expect(rows["anima-preview.safetensors"]).to include("config/comfy.yml")
    expect(rows["mystery-v1.safetensors"]).to include("unknown", "Ask the language model")

    expect { post learned_families_path, params: { model: "mystery-v1.safetensors" } }.to have_enqueued_job(LearnJob)
    family = LearnedFamily.sole
    expect(family).to have_attributes(model: "mystery-v1.safetensors", status: "asking", user: @user)
    get learning_path
    expect(page.at("#models").text).to include("a learned family is asking", "Ask again")
  end

  it "checks a person's edit of a family, tries it, and accepts it only after the trial" do
    family = LearnedFamily.for_model!("mystery-v1.safetensors", user: nil)
    family.update!(status: "failed", error: "gave up")

    patch learned_family_path(family), params: { settings: "{not json" }
    expect(flash[:alert]).to include("That isn't JSON")
    patch learned_family_path(family), params: { settings: JSON.generate(settings.merge("vae" => [ "flux_ae" ])) }
    expect(flash[:alert]).to include("Not saved", "vae")
    patch learned_family_path(family), params: { settings: JSON.generate(settings), label: "Mystery" }
    expect(family.reload).to have_attributes(status: "proposed", label: "Mystery", settings: settings, log: include("Edited by"))

    post learned_family_acceptance_path(family)
    expect(flash[:alert]).to include("Try it first")

    expect { post learned_family_trial_path(family) }.to have_enqueued_job(TrialJob)
    trial = family.trials.sole
    perform_enqueued_jobs
    comfy.finish!(trial.reload.comfy_prompt_id)
    TrialJob.new.perform(trial, client: comfy)
    expect(trial.reload.status).to eq("done")

    post learned_family_acceptance_path(family)
    expect(family.reload).to have_attributes(status: "accepted", accepted_by: @user)
    LearnedFamily.forget!
    get learning_path
    expect(page.css("#models tbody tr").find { |row| row.text.include?("mystery") }.text).to include("Mystery", "learned")
  end

  it "asks for a workflow, checks a person's graph, and lets a kind use it once accepted" do
    post learned_workflows_path, params: { name: "Plain", purpose: "" }
    expect(flash[:alert]).to include("Say what the workflow should do")
    expect { post learned_workflows_path, params: { name: "Plain", purpose: "an ordinary picture" } }.to have_enqueued_job(LearnJob)
    workflow = LearnedWorkflow.sole

    patch learned_workflow_path(workflow), params: { graph: JSON.generate(graph.merge("8" => { "class_type" => "NoSuchNode", "inputs" => {} })) }
    expect(flash[:alert]).to include("Not saved", "NoSuchNode")
    patch learned_workflow_path(workflow), params: { graph: JSON.generate(graph) }
    expect(workflow.reload).to have_attributes(status: "proposed", graph: graph)

    project = make_project
    creature = project.kinds.find_by!(name: "Creature")
    patch project_kind_path(project, creature), params: { kind: { learned_workflow_id: workflow.id } }
    expect(creature.reload.learned_workflow).to be_nil

    workflow.update!(status: "accepted")
    get edit_project_kind_path(project, creature)
    expect(page.at("select[name='kind[learned_workflow_id]']").text).to include("Plain")
    patch project_kind_path(project, creature), params: { kind: { learned_workflow_id: workflow.id } }
    expect(creature.reload.learned_workflow).to eq(workflow)

    get learning_path
    expect(page.at("##{ActionView::RecordIdentifier.dom_id(workflow)}").text).to include("Used by Creature")
    delete learned_workflow_path(workflow)
    expect(creature.reload.learned_workflow_id).to be_nil
  end
end
