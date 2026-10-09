# frozen_string_literal: true

# Builds the ComfyUI workflow (API format) that trains a LoRA on a training
# set (docs/HANDOFF.md "The LoRA loop"), with ComfyUI's own training nodes,
# against what the server has installed:
#
#   the base model, loaded as for a picture (Comfy::Workflow.load)
#   → LoadImageTextDataSetFromFolder (the set baible uploaded: each picture
#     with its caption beside it, as a .txt)
#   → MakeTrainingDataset (the pictures through the VAE, the captions
#     through the text encoder)
#   → ResolutionBucket (pictures of different shapes, trained in buckets)
#   → TrainLoraNode → SaveLoRA (into ComfyUI's output folder, under prefix)
#
# TrainLoraNode has many inputs; the ones baible doesn't set take the
# defaults ComfyUI reports. Raises Comfy::Error, saying what's missing, when
# the server can't make it.
module Comfy
  module Training
    NODES = %w[LoadImageTextDataSetFromFolder MakeTrainingDataset ResolutionBucket TrainLoraNode SaveLoRA].freeze

    module_function

    # folder: the set's folder in ComfyUI's inputs. settings: steps, rank,
    # learning_rate, batch_size.
    def build(model:, family:, folder:, prefix:, settings:, seed:, capabilities:)
      caps = capabilities
      missing = NODES.reject { |node| caps.node?(node) }
      if missing.any?
        raise Error, "This ComfyUI can't train a LoRA: it has no #{missing.to_sentence} node#{'s' if missing.size > 1} (update ComfyUI)"
      end

      graph = {}
      add = Workflow.adder(graph)
      model_out, clip, vae = Workflow.load(add, model, Family.new(family, model), caps)

      set = add.("LoadImageTextDataSetFromFolder", { "folder" => folder })
      encoded = add.("MakeTrainingDataset", { "images" => [ set, 0 ], "vae" => vae, "clip" => clip, "texts" => [ set, 1 ] })
      buckets = add.("ResolutionBucket", { "latents" => [ encoded, 0 ], "conditioning" => [ encoded, 1 ] })
      inputs = caps.defaults("TrainLoraNode").compact.merge(
        "model" => model_out, "latents" => [ buckets, 0 ], "positive" => [ buckets, 1 ],
        "steps" => settings.fetch("steps").to_i, "rank" => settings.fetch("rank").to_i,
        "learning_rate" => settings.fetch("learning_rate").to_f, "batch_size" => settings.fetch("batch_size").to_i,
        "seed" => seed, "bucket_mode" => true, "existing_lora" => "[None]"
      )
      trained = add.("TrainLoraNode", inputs)
      add.("SaveLoRA", { "lora" => [ trained, 0 ], "prefix" => prefix })
      graph
    end
  end
end
