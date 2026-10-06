# frozen_string_literal: true

# The ComfyUI workflow (API format) for one piece of audio, with ACE-Step:
# its checkpoint, a description of the music as tags, the lyrics (or
# "[instrumental]"), so many seconds of empty audio latent, sampled and
# decoded, and saved as MP3 where ComfyUI can, else FLAC. Settings in
# config/comfy.yml under `music`. Raises Comfy::Error when the server can't.
module Comfy
  module Music
    module_function

    NODES = %w[EmptyAceStepLatentAudio TextEncodeAceStepAudio ModelSamplingSD3 VAEDecodeAudio SaveAudio SaveAudioMP3].freeze

    def settings = Comfy.config.fetch(:music, {}).to_h.symbolize_keys

    # The checkpoint when no kind or subject names one.
    def default_model = settings[:model].to_s

    # recipe: "model", "positive" (the tags), "lyrics", "seconds"
    def build(recipe, seed:, prefix:, capabilities:)
      caps = capabilities
      music = settings
      model_name = recipe["model"].presence || default_model
      %w[CheckpointLoaderSimple EmptyAceStepLatentAudio TextEncodeAceStepAudio KSampler VAEDecodeAudio].each do |node|
        caps.node?(node) or raise Error, "ComfyUI has no #{node} node: update ComfyUI for ACE-Step"
      end
      file = caps.find(caps.checkpoints, model_name) or
        raise Error, "#{model_name} isn't on ComfyUI (models/checkpoints): put the ACE-Step checkpoint there"
      save = caps.node?("SaveAudioMP3") ? "SaveAudioMP3" : (caps.node?("SaveAudio") ? "SaveAudio" : raise(Error, "ComfyUI has no SaveAudio node"))

      graph = {}
      id = 0
      add = ->(class_type, inputs) { graph[(id += 1).to_s] = { "class_type" => class_type, "inputs" => inputs }; id.to_s }

      checkpoint = add.("CheckpointLoaderSimple", { "ckpt_name" => file })
      model = [ checkpoint, 0 ]
      model = [ add.("ModelSamplingSD3", { "shift" => music.fetch(:shift, 5.0).to_f, "model" => model }), 0 ] if caps.node?("ModelSamplingSD3")
      latent = [ add.("EmptyAceStepLatentAudio", { "seconds" => recipe.fetch("seconds", 60).to_f, "batch_size" => 1 }), 0 ]
      positive = [ add.("TextEncodeAceStepAudio", { "tags" => recipe["positive"].to_s, "lyrics" => recipe["lyrics"].presence || "[instrumental]",
                                                   "lyrics_strength" => music.fetch(:lyrics_strength, 0.99).to_f, "clip" => [ checkpoint, 1 ] }), 0 ]
      negative = if caps.node?("ConditioningZeroOut")
        [ add.("ConditioningZeroOut", { "conditioning" => positive }), 0 ]
      else
        [ add.("TextEncodeAceStepAudio", { "tags" => "", "lyrics" => "", "lyrics_strength" => 0.0, "clip" => [ checkpoint, 1 ] }), 0 ]
      end
      sampled = [ add.("KSampler", { "seed" => seed, "steps" => music.fetch(:steps, 50).to_i, "cfg" => music.fetch(:cfg, 5.0).to_f,
                                     "sampler_name" => caps.prefer(caps.samplers, %w[euler euler_ancestral]) || "euler",
                                     "scheduler" => caps.prefer(caps.schedulers, %w[simple normal]) || "simple", "denoise" => 1.0,
                                     "model" => model, "positive" => positive, "negative" => negative, "latent_image" => latent }), 0 ]
      audio = [ add.("VAEDecodeAudio", { "samples" => sampled, "vae" => [ checkpoint, 2 ] }), 0 ]
      inputs = { "audio" => audio, "filename_prefix" => prefix }
      inputs["quality"] = music.fetch(:mp3_quality, "V0").to_s if save == "SaveAudioMP3"
      add.(save, inputs)
      graph
    end
  end
end
