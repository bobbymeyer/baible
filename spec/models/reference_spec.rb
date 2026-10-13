# frozen_string_literal: true

require "rails_helper"

# Drawing from a picture as a reference, in a new pose (docs/HANDOFF.md
# "Derived kinds and sheets"): IP-Adapter for SDXL and SD 1.5, an empty
# canvas, and the pose from the prompt.
RSpec.describe "Drawing from a reference" do
  include ActiveJob::TestHelper

  let(:ipadapter_info) do
    {
      "IPAdapterUnifiedLoader" => { "input" => { "required" => { "model" => [ "MODEL" ], "preset" => [ [ "LIGHT - SD1.5 only (low strength)", "STANDARD (medium strength)", "PLUS (high strength)" ] ] } } },
      "IPAdapter" => { "input" => { "required" => {
        "model" => [ "MODEL" ], "ipadapter" => [ "IPADAPTER" ], "image" => [ "IMAGE" ],
        "weight" => [ "FLOAT", { "default" => 1.0, "min" => -1, "max" => 3 } ],
        "start_at" => [ "FLOAT", { "default" => 0.0 } ], "end_at" => [ "FLOAT", { "default" => 1.0 } ],
        "weight_type" => [ [ "standard", "prompt is more important", "style transfer" ] ]
      } } },
      "IPAdapterAdvanced" => { "input" => {
        "required" => { "model" => [ "MODEL" ], "ipadapter" => [ "IPADAPTER" ], "image" => [ "IMAGE" ], "weight" => [ "FLOAT", { "default" => 1.0 } ],
                        "weight_type" => [ [ "linear", "ease in", "style transfer", "composition", "strong style transfer" ] ],
                        "combine_embeds" => [ [ "concat", "add" ] ], "start_at" => [ "FLOAT", { "default" => 0.0 } ],
                        "end_at" => [ "FLOAT", { "default" => 1.0 } ], "embeds_scaling" => [ [ "V only", "K+V" ] ] },
        "optional" => { "clip_vision" => [ "CLIP_VISION" ] }
      } }
    }
  end
  let(:caps) { FakeComfy.capabilities(checkpoints: [ "waiIllustriousSDXL_v150.safetensors" ], extra: ipadapter_info) }
  let(:comfy) { FakeComfy.new(capabilities: caps) }
  let(:project) { make_project(model: "waiIllustriousSDXL_v150.safetensors") }
  let!(:battle) { project.kinds.create!(name: "Battle sprite", parent: project.kinds.find_by!(name: "Character"), derive: "reference", derive_weight: 0.7, prompt: "battle stance") }
  let(:cid) { make_subject(project, "Character", "Cid", notes: "red coat") }

  before { allow(Comfy).to receive(:capabilities).and_return(caps) }

  def pick!(subject, seed: 7)
    Pick.new(subject: subject, seed: seed, current: true, recipe: { "medium" => "image" }).tap do |pick|
      pick.file.attach(io: StringIO.new(FakeComfy.png), filename: "#{subject.name.parameterize}-#{seed}.png", content_type: "image/png")
      pick.save!
    end
  end

  it "draws a derived subject from its parent's picture through IP-Adapter, on an empty canvas" do
    drawn = pick!(cid, seed: 42)
    sprite = make_subject(project, "Battle sprite", "Cid", parent: cid, notes: "lunging, sword raised")
    batch = Batch.start!(sprite, count: 1, draft: true)
    expect(batch.candidates.sole.seed).not_to eq(42) # not the picture's noise: that brings back its pose
    expect(batch.recipe).to include("source" => { "pick_id" => drawn.id, "use" => "reference", "label" => "Cid" }, "reference_weight" => 0.7)
    expect(batch.recipe).not_to have_key("denoise")
    expect(batch.draft?).to be(false)
    expect(batch.source_label).to eq("drawn from Cid, in a new pose")

    BatchJob.new.perform(batch, client: comfy)
    graph = comfy.submitted.last
    nodes = graph.values.map { |node| node["class_type"] }
    expect(nodes).to include("IPAdapterUnifiedLoader", "IPAdapterAdvanced", "LoadImage", "EmptyLatentImage")
    expect(nodes).not_to include("VAEEncode")
    loader = graph.find { |_, node| node["class_type"] == "IPAdapterUnifiedLoader" }
    expect(loader.last["inputs"]["preset"]).to eq("PLUS (high strength)")
    adapter = graph.find { |_, node| node["class_type"] == "IPAdapterAdvanced" }
    # Its design, not its composition: the pose is the prompt's.
    expect(adapter.last["inputs"]).to include("weight" => 0.7, "start_at" => 0.0, "end_at" => 1.0, "weight_type" => "strong style transfer",
                                              "combine_embeds" => "concat", "ipadapter" => [ loader.first, 1 ], "model" => [ loader.first, 0 ])
    image = graph[adapter.last.dig("inputs", "image").first]
    expect(image).to include("class_type" => "LoadImage", "inputs" => { "image" => batch.reload.recipe["source_image"] })
    sampler = graph.values.find { |node| node["class_type"] == "KSampler" }
    expect(sampler["inputs"]).to include("denoise" => 1, "model" => [ adapter.first, 0 ])
    expect(graph[sampler.dig("inputs", "latent_image").first]["class_type"]).to eq("EmptyLatentImage")

    comfy.finish!(batch.candidates.sole.comfy_prompt_id)
    BatchJob.new.perform(batch, client: comfy)
    pick = batch.candidates.sole.pick!
    expect(pick.sidecar["source"]).to eq("label" => "Cid", "use" => "reference", "weight" => 0.7)

    # An older ComfyUI_IPAdapter_plus, without the advanced node: IPAdapter, weighted for style.
    older = FakeComfy.new(capabilities: FakeComfy.capabilities(checkpoints: [ "waiIllustriousSDXL_v150.safetensors" ], extra: ipadapter_info.except("IPAdapterAdvanced"),
                                                               nodes: Comfy::Capabilities::NODES - %w[IPAdapterAdvanced]))
    BatchJob.new.perform(Batch.start!(sprite, count: 1), client: older)
    simple = older.submitted.last.values.find { |node| node["class_type"] == "IPAdapter" }
    expect(simple["inputs"]).to include("weight_type" => "style transfer")
  end

  it "uses an Illustrious IP-Adapter by file when the server has one, and the unified loader when it hasn't" do
    pick!(cid)
    sprite = make_subject(project, "Battle sprite", "Cid", parent: cid)
    files = {
      "IPAdapterModelLoader" => { "input" => { "required" => { "ipadapter_file" => [ [ "ip-adapter-plus_sdxl_vit-h.safetensors", "noobIPAMARK1_mark1.safetensors" ] ] } } },
      "CLIPVisionLoader" => { "input" => { "required" => { "clip_name" => [ [ "CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors", "CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors" ] ] } } },
      "IPAdapterAdvanced" => { "input" => {
        "required" => { "model" => [ "MODEL" ], "ipadapter" => [ "IPADAPTER" ], "image" => [ "IMAGE" ], "weight" => [ "FLOAT", { "default" => 1.0 } ],
                        "weight_type" => [ [ "linear", "ease in" ] ], "combine_embeds" => [ [ "concat", "add" ] ],
                        "start_at" => [ "FLOAT", { "default" => 0.0 } ], "end_at" => [ "FLOAT", { "default" => 1.0 } ],
                        "embeds_scaling" => [ [ "V only", "K+V" ] ] },
        "optional" => { "clip_vision" => [ "CLIP_VISION" ] }
      } }
    }
    illustrious = FakeComfy.new(capabilities: FakeComfy.capabilities(checkpoints: [ "waiIllustriousSDXL_v150.safetensors" ], extra: ipadapter_info.merge(files)))
    batch = Batch.start!(sprite, count: 1)
    BatchJob.new.perform(batch, client: illustrious)
    graph = illustrious.submitted.last
    nodes = graph.transform_values { |node| node["class_type"] }.invert
    expect(graph[nodes["IPAdapterModelLoader"]]["inputs"]).to eq("ipadapter_file" => "noobIPAMARK1_mark1.safetensors")
    expect(graph[nodes["CLIPVisionLoader"]]["inputs"]).to eq("clip_name" => "CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors")
    expect(graph[nodes["IPAdapterAdvanced"]]["inputs"]).to include(
      "weight" => 0.7, "weight_type" => "linear", # none it prefers on this server's node: the node's default "combine_embeds" => "concat", "embeds_scaling" => "V only",
      "ipadapter" => [ nodes["IPAdapterModelLoader"], 0 ], "clip_vision" => [ nodes["CLIPVisionLoader"], 0 ]
    )
    expect(nodes).not_to have_key("IPAdapterUnifiedLoader")

    # A plain SDXL model, or no Illustrious file: the unified loader's preset.
    plain = FakeComfy.new(capabilities: FakeComfy.capabilities(checkpoints: [ "waiIllustriousSDXL_v150.safetensors" ],
                                                               extra: ipadapter_info.merge(files.merge("IPAdapterModelLoader" => { "input" => { "required" => { "ipadapter_file" => [ [ "ip-adapter-plus_sdxl_vit-h.safetensors" ] ] } } }))))
    batch = Batch.start!(sprite, count: 1)
    BatchJob.new.perform(batch, client: plain)
    expect(plain.submitted.last.values.map { |node| node["class_type"] }).to include("IPAdapterUnifiedLoader", "IPAdapterAdvanced")
    expect(plain.submitted.last.values.map { |node| node["class_type"] }).not_to include("IPAdapterModelLoader")
  end

  it "draws a variant from its own subject's picture, in its pose" do
    sprite = make_subject(project, "Battle sprite", "Cid", parent: cid)
    attack = sprite.variants.create!(name: "attack", prompt: "lunging forward")
    own = pick!(sprite, seed: 9)
    expect(Batch.start!(sprite, variant: attack, count: 1).recipe).to include("source" => include("pick_id" => own.id, "use" => "reference"))
  end

  it "says what's missing: IP-Adapter's nodes, or a model it works with" do
    pick!(cid)
    sprite = make_subject(project, "Battle sprite", "Cid", parent: cid)

    bare = FakeComfy.new(capabilities: FakeComfy.capabilities(checkpoints: [ "waiIllustriousSDXL_v150.safetensors" ],
                                                              nodes: Comfy::Capabilities::NODES - %w[IPAdapter IPAdapterUnifiedLoader]))
    batch = Batch.start!(sprite, count: 1)
    BatchJob.new.perform(batch, client: bare)
    expect(batch.reload).to have_attributes(status: "failed", error: include("install ComfyUI_IPAdapter_plus"))

    project.update!(model: "anima-preview.safetensors")
    batch = Batch.start!(sprite.reload, count: 1)
    BatchJob.new.perform(batch, client: FakeComfy.new(capabilities: FakeComfy.capabilities(extra: ipadapter_info)))
    expect(batch.reload).to have_attributes(status: "failed", error: include("built for SDXL and SD 1.5", "Anima isn't one"))
  end

  it "draws any pick as a reference when asked in the studio", type: :request do
    allow(Comfy).to receive(:client).and_return(comfy)
    drawn = pick!(cid)
    goblin = make_subject(project, "Creature", "Goblin")
    post subject_batches_path(goblin), params: { count: 1, from_pick_id: drawn.id, use: "reference", weight: "0.5" }
    expect(goblin.batch_for.recipe).to include("source" => include("pick_id" => drawn.id, "use" => "reference"), "reference_weight" => 0.5)

    # Ticked with the kind's own start chosen, on a kind that redraws: drawn from instead.
    battle.update!(derive: "picture")
    sprite = make_subject(project, "Battle sprite", "Cid", parent: cid)
    post subject_batches_path(sprite), params: { count: 1, from_pick_id: "derived", use: "reference" }
    expect(sprite.batch_for.recipe).to include("source" => include("pick_id" => drawn.id, "use" => "reference"), "reference_weight" => 0.7)
    expect(sprite.batch_for.recipe).not_to have_key("denoise")
    post subject_batches_path(sprite), params: { count: 1, from_pick_id: "derived" }
    expect(sprite.batch_for.recipe).to include("source" => { "pick_id" => drawn.id, "label" => "Cid" }, "denoise" => 0.45)

    battle.update!(derive: "reference")
    get subject_path(sprite)
    expect(page.at("#from_pick_id option[selected]").text).to include("Cid's picture, drawn from in a new pose")
    get project_kinds_path(project)
    expect(page.at("##{ActionView::RecordIdentifier.dom_id(battle)}").text).to include("Character: draw from its picture, in a new pose, weight 0.7")
  end
end
