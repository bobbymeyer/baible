# frozen_string_literal: true

require "rails_helper"

# The language model learning a family or writing a workflow, and baible
# using what a person accepted (docs/HANDOFF.md "Unknown models and new
# workflows").
RSpec.describe "Learning" do
  include ActiveJob::TestHelper

  let(:caps) { FakeComfy.capabilities(diffusion_models: [ "anima-preview.safetensors", "mystery-v1.safetensors" ]) }
  let(:comfy) { FakeComfy.new(capabilities: caps) }
  let(:good) do
    { "label" => "Mystery", "text_encoder" => [ "qwen_3_06b" ], "clip_type" => [ "anima" ], "vae" => [ "qwen_image_vae" ], "lora" => "model",
      "steps" => 28, "cfg" => 4.0, "sampler" => [ "euler" ], "scheduler" => [ "simple" ], "negative" => true, "prefix" => "",
      "negative_prefix" => "", "prompt_style" => "prose", "pixels" => [ 786_432, 1_310_720 ], "multiple" => 16 }
  end

  before { allow(Comfy).to receive(:capabilities).and_return(caps) }

  it "has the language model propose a family, sends back what fails the checks, and uses it only once accepted" do
    family = LearnedFamily.for_model!("mystery-v1.safetensors", user: nil)
    llm = ScriptedLlm.new(JSON.generate(good.merge("vae" => [ "flux_ae" ])), JSON.generate(good))
    FamilyWriter.propose!(family, client: comfy, llm: llm)

    expect(family.reload).to have_attributes(status: "proposed", label: "Mystery", settings: good.except("label"))
    expect(llm.asked.last[:user]).to include("Your last answer had these problems", "vae: none of [\"flux_ae\"]")
    expect(llm.asked.first[:user]).to include("mystery-v1.safetensors, in models/diffusion_models", "Samplers: euler")
    expect(family.log).to include("Attempt 1", "Attempt 2")

    expect(Comfy::Family.match("mystery-v1.safetensors")).to be_nil # proposed: not used yet
    expect { family.accept!(nil) }.to raise_error(Refusal, /Try it first/)

    trial = family.trials.create!(prompt: Trial::PROMPT, seed: 1)
    TrialJob.new.perform(trial, client: comfy)
    graph = comfy.submitted.last
    expect(graph.values.map { |node| node["class_type"] }).to include("UNETLoader", "CLIPLoader", "SaveImage")
    expect(graph.values.find { |node| node["class_type"] == "KSampler" }["inputs"]).to include("steps" => 28, "cfg" => 4.0, "sampler_name" => "euler")
    comfy.finish!(trial.reload.comfy_prompt_id)
    TrialJob.new.perform(trial, client: comfy)
    expect(trial.reload).to have_attributes(status: "done", image: be_attached)

    family.accept!(nil)
    LearnedFamily.forget!
    expect(Comfy::Family.match("mystery-v1.safetensors")).to eq(family.slug)
    expect(Comfy::Family.for("mystery-v1.safetensors").label).to eq("Mystery")
  end

  it "fails a family after three answers that don't pass, and keeps why" do
    family = LearnedFamily.for_model!("mystery-v1.safetensors", user: nil)
    bad = JSON.generate(good.merge("steps" => 0))
    FamilyWriter.propose!(family, client: comfy, llm: ScriptedLlm.new(bad, bad, bad))
    expect(family.reload).to have_attributes(status: "failed", error: include("3 answers"))
  end

  it "has the language model write a workflow from the server's own nodes, and fixes what fails the checks" do
    workflow = LearnedWorkflow.create!(name: "Plain SDXL", purpose: "an ordinary picture with SDXL", status: "asking")
    graph = {
      "1" => { "class_type" => "CheckpointLoaderSimple", "inputs" => { "ckpt_name" => "{{model}}" } },
      "2" => { "class_type" => "CLIPTextEncode", "inputs" => { "text" => "{{prompt}}", "clip" => [ "1", 1 ] } },
      "3" => { "class_type" => "CLIPTextEncode", "inputs" => { "text" => "{{negative}}", "clip" => [ "1", 1 ] } },
      "4" => { "class_type" => "EmptyLatentImage", "inputs" => { "width" => "{{width}}", "height" => "{{height}}", "batch_size" => 1 } },
      "5" => { "class_type" => "KSampler", "inputs" => { "model" => [ "1", 0 ], "seed" => "{{seed}}", "steps" => 25, "cfg" => 6.0,
                                                           "sampler_name" => "euler", "scheduler" => "normal", "positive" => [ "2", 0 ],
                                                           "negative" => [ "3", 0 ], "latent_image" => [ "4", 0 ], "denoise" => 1.0 } },
      "6" => { "class_type" => "VAEDecode", "inputs" => { "samples" => [ "5", 0 ], "vae" => [ "1", 2 ] } },
      "7" => { "class_type" => "SaveImage", "inputs" => { "images" => [ "6", 0 ], "filename_prefix" => "{{prefix}}" } }
    }
    broken = graph.deep_dup.tap { |g| g["5"]["inputs"]["sampler_name"] = "turbo" }
    llm = ScriptedLlm.new(JSON.generate("nodes" => %w[CheckpointLoaderSimple KSampler NoSuchNode]),
                          JSON.generate("graph" => broken), JSON.generate("graph" => graph))
    WorkflowWriter.propose!(workflow, client: comfy, llm: llm)

    expect(workflow.reload).to have_attributes(status: "proposed", graph: graph,
                                               outline: start_with("CheckpointLoaderSimple → CLIPTextEncode ×2"))
    expect(llm.asked.first[:user]).to include("Every node on this server: CLIPTextEncode, CheckpointLoaderSimple")
    expect(llm.asked.second[:user]).to include("KSampler: {\"inputs\"")
    expect(llm.asked.third[:user]).to include("\"turbo\" isn't one of its choices")
    expect(workflow.log).to include("Nodes asked for: CheckpointLoaderSimple, KSampler, NoSuchNode")
  end

  it "makes a kind's batches with an accepted workflow, frozen into the recipe and checked before anything is queued" do
    project = make_project
    graph = {
      "1" => { "class_type" => "CheckpointLoaderSimple", "inputs" => { "ckpt_name" => "{{model}}" } },
      "2" => { "class_type" => "CLIPTextEncode", "inputs" => { "text" => "{{prompt}}", "clip" => [ "1", 1 ] } },
      "4" => { "class_type" => "EmptyLatentImage", "inputs" => { "width" => "{{width}}", "height" => "{{height}}", "batch_size" => 1 } },
      "5" => { "class_type" => "KSampler", "inputs" => { "model" => [ "1", 0 ], "seed" => "{{seed}}", "steps" => 25, "cfg" => 6.0,
                                                           "sampler_name" => "euler", "scheduler" => "normal", "positive" => [ "2", 0 ],
                                                           "negative" => [ "2", 0 ], "latent_image" => [ "4", 0 ], "denoise" => 1.0 } },
      "6" => { "class_type" => "VAEDecode", "inputs" => { "samples" => [ "5", 0 ], "vae" => [ "1", 2 ] } },
      "7" => { "class_type" => "SaveImage", "inputs" => { "images" => [ "6", 0 ], "filename_prefix" => "{{prefix}}" } }
    }
    workflow = LearnedWorkflow.create!(name: "Plain", purpose: "plain", graph: graph, status: "proposed")
    kind = project.kinds.find_by!(name: "Creature")
    expect(kind.update(learned_workflow: workflow)).to be(false) # not accepted yet
    workflow.update!(status: "accepted")
    kind.update!(learned_workflow: workflow, model: "sdxl.safetensors")

    goblin = make_subject(project, "Creature", "Goblin", notes: "a rusty knife")
    batch = Batch.start!(goblin, count: 1, draft: true)
    expect(batch.recipe["draft"]).to be_nil
    expect(batch.recipe["transparent"]).to be(false)
    expect(batch.recipe.dig("learned_workflow", "graph")).to eq(graph)

    workflow.update!(graph: {}) # later edits don't touch a frozen recipe
    BatchJob.new.perform(batch, client: comfy)
    sent = comfy.submitted.last
    expect(sent["2"]["inputs"]["text"]).to include("Goblin, a rusty knife")
    expect(sent["5"]["inputs"]["seed"]).to eq(batch.candidates.first.seed)
    expect(sent["7"]["inputs"]["filename_prefix"]).to start_with("baible/goblin-")

    elsewhere = FakeComfy.new(capabilities: caps).tap { |c| c.definitions = FakeComfy.definitions.except("KSampler") }
    other = Batch.start!(goblin, count: 1)
    BatchJob.new.perform(other, client: elsewhere)
    expect(other.reload).to have_attributes(status: "failed", error: include("won't run here", "no KSampler node"))
  end
end
