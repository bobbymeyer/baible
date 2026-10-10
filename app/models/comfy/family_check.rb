# frozen_string_literal: true

# Whether a proposed family (LearnedFamily, from the language model or a
# person) can run a model on this ComfyUI (docs/HANDOFF.md "Unknown models
# and new workflows"): every file it asks for is on the server, every choice
# is one the server offers, every number is in a sane range. Returns the
# problems, in words the language model can act on; none means it can run.
module Comfy
  module FamilyCheck
    PROMPT_STYLES = %w[tags prose].freeze
    LORA = %w[model model_and_clip].freeze
    LATENTS = %w[EmptyLatentImage EmptySD3LatentImage].freeze
    MULTIPLES = [ 8, 16, 32, 64 ].freeze

    module_function

    def errors(settings, model:, capabilities:)
      caps = capabilities
      s = settings.to_h.stringify_keys
      problems = []
      list = ->(key) { Array(s[key]).map(&:to_s).reject(&:empty?) }

      if caps.diffusion_model?(model)
        problems << "text_encoder: none of #{list.('text_encoder').inspect} names a file in models/text_encoders (#{caps.text_encoders.join(', ')})" unless caps.find_like(caps.text_encoders, list.("text_encoder"))
        problems << "clip_type: none of #{list.('clip_type').inspect} is a CLIPLoader type here (#{caps.clip_types.join(', ')})" unless caps.prefer(caps.clip_types, list.("clip_type"))
        problems << "vae: none of #{list.('vae').inspect} names a file in models/vae (#{caps.vaes.join(', ')})" unless caps.find_like(caps.vaes, list.("vae"))
      elsif !caps.checkpoint?(model)
        problems << "#{model} isn't on this ComfyUI"
      end
      problems << "sampler: none of #{list.('sampler').inspect} is a KSampler sampler here" unless caps.prefer(caps.samplers, list.("sampler"))
      problems << "scheduler: none of #{list.('scheduler').inspect} is a KSampler scheduler here" unless caps.prefer(caps.schedulers, list.("scheduler"))
      problems << "steps must be a whole number from 1 to 150" unless s["steps"].is_a?(Integer) && s["steps"].between?(1, 150)
      problems << "cfg must be a number from 1 to 30" unless s["cfg"].is_a?(Numeric) && s["cfg"].to_f.between?(1, 30)
      problems << "prompt_style must be one of #{PROMPT_STYLES.join(', ')}" unless PROMPT_STYLES.include?(s["prompt_style"])
      problems << "lora must be one of #{LORA.join(', ')}" unless LORA.include?(s["lora"])
      problems << "negative must be true or false" unless [ true, false ].include?(s["negative"])
      problems << "multiple must be one of #{MULTIPLES.join(', ')}" unless MULTIPLES.include?(s["multiple"])
      low, high = Array(s["pixels"])
      unless low.is_a?(Integer) && high.is_a?(Integer) && low.between?(65_536, 16_777_216) && high.between?(low, 16_777_216)
        problems << "pixels must be [low, high] whole numbers of pixels, low <= high (1024x1024 is 1048576)"
      end
      if s.key?("latent") && !(LATENTS.include?(s["latent"]) && caps.node?(s["latent"]))
        problems << "latent must be one of #{LATENTS.select { |node| caps.node?(node) }.join(', ')}"
      end
      if s.key?("clip_skip") && !(s["clip_skip"].is_a?(Integer) && s["clip_skip"].between?(1, 4))
        problems << "clip_skip must be a whole number from 1 to 4"
      end
      %w[prefix negative_prefix].each { |key| problems << "#{key} must be text" if s.key?(key) && !s[key].is_a?(String) }
      problems
    end
  end
end
