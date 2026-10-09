# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comfy::Training do
  let(:train_info) do
    { "input" => { "required" => {
      "model" => [ "MODEL" ], "steps" => [ "INT", { "default" => 16 } ], "optimizer" => [ [ "AdamW", "SGD" ], { "default" => "AdamW" } ],
      "training_dtype" => [ "COMBO", { "options" => %w[bf16 fp32], "default" => "bf16" } ], "gradient_checkpointing" => [ "BOOLEAN", { "default" => true } ]
    } } }
  end
  let(:caps) { FakeComfy.capabilities(checkpoints: [ "ponyDiffusionV6XL.safetensors" ], extra: { "TrainLoraNode" => train_info }) }
  let(:settings) { { "steps" => 1200, "rank" => 32, "learning_rate" => 0.0002, "batch_size" => 2 } }

  def build(model, family)
    described_class.build(model: model, family: family, folder: "baible/train/x-v1", prefix: "loras/baible/x-v1",
                          settings: settings, seed: 7, capabilities: caps)
  end

  it "fills what it doesn't set from ComfyUI's defaults, and sets the rest from the run" do
    trainer = build("anima-preview.safetensors", "anima").values.find { |node| node["class_type"] == "TrainLoraNode" }["inputs"]
    expect(trainer).to include("optimizer" => "AdamW", "training_dtype" => "bf16", "gradient_checkpointing" => true,
                               "steps" => 1200, "rank" => 32, "learning_rate" => 0.0002, "batch_size" => 2, "seed" => 7)
    expect(trainer["model"]).to eq([ "1", 0 ])
  end

  it "loads a checkpoint the way a picture would, its text encoder and VAE included" do
    graph = build("ponyDiffusionV6XL.safetensors", "sdxl")
    dataset = graph.values.find { |node| node["class_type"] == "MakeTrainingDataset" }["inputs"]
    expect(graph["1"]["class_type"]).to eq("CheckpointLoaderSimple")
    expect(dataset).to include("clip" => [ "1", 1 ], "vae" => [ "1", 2 ], "images" => [ "2", 0 ], "texts" => [ "2", 1 ])
    expect(graph["2"]["inputs"]).to eq("folder" => "baible/train/x-v1")
  end
end
