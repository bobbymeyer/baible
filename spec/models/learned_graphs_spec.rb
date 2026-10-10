# frozen_string_literal: true

require "rails_helper"

# Checking what the language model proposes against the server
# (docs/HANDOFF.md "Unknown models and new workflows").
RSpec.describe "Checking proposals" do
  let(:defs) { FakeComfy.definitions }
  let(:graph) do
    {
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
  end

  describe Comfy::GraphCheck do
    it "passes a graph the server can run, placeholders and all" do
      expect(described_class.errors(graph, defs)).to eq([])
    end

    it "names every problem in words the language model can act on" do
      bad = graph.deep_dup
      bad["5"]["inputs"].merge!("sampler_name" => "nope", "steps" => 0, "positive" => [ "6", 0 ], "colour" => "red")
      bad["6"]["inputs"].delete("vae")
      bad["8"] = { "class_type" => "Upscaler9000", "inputs" => {} }
      bad["4"]["inputs"]["width"] = "{{prompt}}"
      bad["7"]["inputs"]["filename_prefix"] = "out"
      expect(described_class.errors(bad, defs)).to contain_exactly(
        "node 4 (EmptyLatentImage) input width: {{prompt}} is string, but this input takes int",
        "node 5 (KSampler) input steps: must be at least 1",
        "node 5 (KSampler) input sampler_name: \"nope\" isn't one of its choices (euler, dpmpp_2m)",
        "node 5 (KSampler) input positive: takes CONDITIONING, but output 0 of node 6 gives IMAGE",
        "node 5 (KSampler): it has no input called colour",
        "node 6 (VAEDecode): the required input vae is missing",
        "node 8: there is no Upscaler9000 node on this ComfyUI",
        "nothing saves the picture: a SaveImage node needs filename_prefix \"{{prefix}}\""
      )
    end

    it "fills placeholders with their typed values, and checks the filled graph's files" do
      filled = Comfy::Template.fill(graph, "prompt" => "a goblin", "negative" => "", "seed" => 7, "width" => 832, "height" => 1216,
                                           "prefix" => "baible/goblin-7", "model" => "sdxl.safetensors")
      expect(filled["5"]["inputs"]["seed"]).to eq(7)
      expect(filled["4"]["inputs"]).to include("width" => 832, "height" => 1216)
      expect(described_class.errors(filled, defs, template: false)).to eq([])

      elsewhere = Comfy::Template.fill(graph, filled.values.first.then { { "prompt" => "x", "negative" => "", "seed" => 1, "width" => 8,
                                                                          "height" => 8, "prefix" => "p", "model" => "gone.safetensors" } })
      expect(described_class.errors(elsewhere, defs, template: false)).to include(
        "node 1 (CheckpointLoaderSimple) input ckpt_name: \"gone.safetensors\" isn't one of its choices (sdxl.safetensors)",
        "node 4 (EmptyLatentImage) input width: must be at least 16"
      )
      expect { Comfy::Template.fill(graph, {}) }.to raise_error(Comfy::Error, /needs \{\{model\}\}/)
    end
  end

  describe Comfy::FamilyCheck do
    let(:caps) { FakeComfy.capabilities(diffusion_models: [ "mystery-v1.safetensors" ]) }
    let(:good) do
      { "text_encoder" => [ "qwen_3_06b" ], "clip_type" => [ "anima" ], "vae" => [ "qwen_image_vae" ], "lora" => "model", "steps" => 28,
        "cfg" => 4.0, "sampler" => [ "euler" ], "scheduler" => [ "simple" ], "negative" => true, "prompt_style" => "tags",
        "pixels" => [ 786_432, 1_310_720 ], "multiple" => 16 }
    end

    it "passes settings the server can run, and names what it can't" do
      expect(described_class.errors(good, model: "mystery-v1.safetensors", capabilities: caps)).to eq([])
      bad = good.merge("vae" => [ "flux_ae" ], "cfg" => 0, "sampler" => [ "magic" ], "pixels" => [ 10, 5 ], "prompt_style" => "poetry")
      expect(described_class.errors(bad, model: "mystery-v1.safetensors", capabilities: caps)).to contain_exactly(
        "vae: none of [\"flux_ae\"] names a file in models/vae (qwen_image_vae.safetensors)",
        "sampler: none of [\"magic\"] is a KSampler sampler here",
        "cfg must be a number from 1 to 30",
        "prompt_style must be one of tags, prose",
        "pixels must be [low, high] whole numbers of pixels, low <= high (1024x1024 is 1048576)"
      )
    end
  end
end
