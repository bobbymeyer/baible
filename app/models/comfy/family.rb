# frozen_string_literal: true

# How a family of image model wants to be run (config/comfy.yml `families`):
# its loaders, sampling, prompt conventions and trained size range. A model's
# file name picks its family; anything the name also matches in `variants`
# (Turbo, Pony, Lightning) is laid over it. Comfy::Workflow reads it to
# build the graph.
module Comfy
  class Family
    attr_reader :slug, :settings

    def self.configured
      Comfy.config.fetch(:families, {}).to_h.deep_stringify_keys
    end

    # The family for a model file. A name no family matches goes by where
    # the file is on ComfyUI, when that's known (capabilities, or a lambda
    # giving them, only called when the name alone doesn't settle it).
    def self.for(model, capabilities: nil)
      name = File.basename(model.to_s).downcase
      slug = configured.find { |_, family| matches?(family["match"], name) }&.first
      capabilities = capabilities.call if !slug && capabilities.respond_to?(:call)
      slug ||= Comfy.config[:checkpoint_family].to_s if capabilities.respond_to?(:checkpoint?) && capabilities.checkpoint?(model)
      slug ||= Comfy.config[:default_family].to_s
      new(slug, model)
    end

    # The named family, or nil when config no longer has it (an old recipe).
    def self.find(slug, model = nil)
      configured.key?(slug.to_s) ? new(slug, model) : nil
    end

    def self.matches?(patterns, name)
      Array(patterns).any? { |pattern| name.include?(pattern.to_s.downcase) }
    end

    def initialize(slug, model = nil)
      @slug = slug.to_s
      base = self.class.configured.fetch(@slug) { raise Error, "No model family called #{@slug.inspect} in config/comfy.yml" }
      name = File.basename(model.to_s).downcase
      @settings = Array(base["variants"]).select { |variant| self.class.matches?(variant["match"], name) }
                                         .reduce(base.except("variants")) { |all, variant| all.merge(variant.except("match")) }
    end

    def label = settings["label"] || slug.humanize
    def steps = settings.fetch("steps", 25).to_i
    def cfg = settings.fetch("cfg", 6.0).to_f
    def prefix = settings["prefix"].to_s
    def negative_prefix = settings["negative_prefix"].to_s
    def clip_skip = settings["clip_skip"].to_i
    def samplers = Array(settings["sampler"])
    def schedulers = Array(settings["scheduler"])
    def text_encoders = Array(settings["text_encoder"])
    def clip_types = Array(settings["clip_type"])
    def vaes = Array(settings["vae"])
    def vae_overrides = Array(settings["vae_override"])
    def latent = settings["latent"].presence || "EmptyLatentImage"
    # How the family likes its prompt: "tags" (booru-style) or "prose".
    def prompt_style = settings["prompt_style"].presence || "prose"

    # LoRAs patch the model alone, or the text encoder too.
    def lora_clip? = settings["lora"] == "model_and_clip"

    # Only encode a negative prompt when the sampler will use one: at cfg 1
    # it is ignored, and encoding it can cost more than the image (a big
    # text encoder on CPU).
    def negative?
      settings.fetch("negative", true) && cfg > 1.0
    end

    # A size scaled into the trained range, keeping its shape, rounded to
    # what the model's latent grid wants.
    def size(width, height)
      low, high = Array(settings["pixels"]).map(&:to_i)
      multiple = settings.fetch("multiple", 8).to_i
      area = width.to_f * height
      scale = if low && area < low then Math.sqrt(low / area)
      elsif high && area > high then Math.sqrt(high / area)
      else 1.0
      end
      # Rounded away from the edge it was scaled to, so it stays in range.
      round = if scale > 1 then :ceil elsif scale < 1 then :floor else :round end
      [ width, height ].map { |side| [ ((side * scale) / multiple).public_send(round) * multiple, multiple ].max }
    end

    # --- drafts ---------------------------------------------------------------

    def draft_config = Comfy.config.fetch(:draft, {}).to_h.stringify_keys

    # Fewer steps for a quick look; a turbo model already takes few.
    def draft_steps
      settings["draft_steps"]&.to_i || [ draft_config.fetch("steps", 16).to_i, steps ].min
    end

    # A rough picture of about draft.pixels (512 × 512), the same shape as
    # the full one, below the trained range on purpose.
    def draft_size(width, height)
      full = size(width, height)
      target = draft_config.fetch("pixels", 262_144).to_f
      scale = [ Math.sqrt(target / (full[0] * full[1])), 1.0 ].min
      multiple = settings.fetch("multiple", 8).to_i
      full.map { |side| [ ((side * scale) / multiple).round * multiple, multiple ].max }
    end

    # How much a refinement re-noises the draft it starts from.
    def refine_denoise = draft_config.fetch("denoise", 0.6).to_f.clamp(0.1, 1.0)

    # One line for the pages: what running this family means.
    def summary
      [ label, "#{steps} steps", "CFG #{cfg.to_s.delete_suffix('.0')}", ("CLIP skip #{clip_skip}" if clip_skip > 1),
        ("no negative prompt" unless negative?) ].compact.join(" · ")
    end
  end
end
