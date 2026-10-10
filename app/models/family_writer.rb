# frozen_string_literal: true

# Asks the language model how to run a model config/comfy.yml doesn't know
# (docs/HANDOFF.md "Unknown models and new workflows"), from what the server
# reports: the model's file and folder, and the text encoders, CLIP types,
# VAEs, samplers and schedulers it has, with two configured families as
# examples. Each answer is checked against the server (Comfy::FamilyCheck);
# a failing one is sent back with its problems, up to ATTEMPTS times. The
# result is a proposal, never used until a person accepts it.
module FamilyWriter
  ATTEMPTS = 3
  EXAMPLES = %w[anima sdxl].freeze

  SYSTEM = <<~TEXT.squish
    You configure how an image model runs in ComfyUI. Reply with one JSON object and nothing else, with these keys:
    label (a short name for the model's family), text_encoder (file-name fragments of its text encoder, best first),
    clip_type (CLIPLoader types, best first), vae (file-name fragments of its VAE, best first), lora ("model" or "model_and_clip"),
    steps (integer), cfg (number; 1.0 for distilled or turbo models), sampler (KSampler samplers, best first),
    scheduler (KSampler schedulers, best first), negative (true if it uses a negative prompt), prefix (quality words that lead
    its prompts, or ""), negative_prefix (or ""), prompt_style ("tags" for booru-tag models, "prose" otherwise),
    pixels ([low, high] total pixels it was trained on), multiple (8, 16, 32 or 64), and optionally latent
    ("EmptyLatentImage" or "EmptySD3LatentImage") and clip_skip. Choose only from what the server has.
    If unsure, prefer the safest common values.
  TEXT

  module_function

  def propose!(family, client:, llm:)
    caps = client.capabilities
    raise Comfy::Error, caps.error || "ComfyUI isn't answering" unless caps.reachable?

    user = facts(family.model, caps)
    ATTEMPTS.times do |attempt|
      answer = llm.json(system: SYSTEM, user: user, temperature: 0.2, max_tokens: 1200)
      settings = answer.to_h.stringify_keys
      label = settings.delete("label").to_s.strip.presence
      settings = settings.slice(*LearnedFamily::KEYS)
      problems = Comfy::FamilyCheck.errors(settings, model: family.model, capabilities: caps)
      family.note!("Attempt #{attempt + 1}: #{JSON.generate(answer)}#{"\nProblems: #{problems.join('; ')}" if problems.any?}")
      if problems.empty?
        return family.update!(status: "proposed", settings: settings, label: label || family.label, error: nil)
      end

      user = "#{facts(family.model, caps)}\n\nYour last answer had these problems; answer again with the whole JSON:\n- #{problems.join("\n- ")}"
    end
    family.update!(status: "failed", error: "The language model's #{ATTEMPTS} answers didn't pass the server's checks: see the log.")
  end

  def facts(model, caps)
    where = caps.diffusion_model?(model) ? "models/diffusion_models (a bare diffusion model: it needs a text encoder and a VAE)" : "models/checkpoints (a checkpoint with its own text encoder and VAE)"
    examples = Comfy::Family.config_families.slice(*EXAMPLES).transform_values { |family| family.except("variants", "match") }
    <<~TEXT
      The model: #{model}, in #{where}.
      Text encoders on the server: #{caps.text_encoders.join(', ').presence || 'none'}
      CLIPLoader types: #{caps.clip_types.join(', ').presence || 'none'}
      VAEs: #{caps.vaes.join(', ').presence || 'none'}
      Samplers: #{caps.samplers.join(', ')}
      Schedulers: #{caps.schedulers.join(', ')}
      Latent nodes: #{Comfy::FamilyCheck::LATENTS.select { |node| caps.node?(node) }.join(', ')}
      Families already configured, as examples: #{JSON.generate(examples)}
    TEXT
  end
end
