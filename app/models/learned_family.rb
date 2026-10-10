# frozen_string_literal: true

# How to run a model config/comfy.yml doesn't know (docs/HANDOFF.md
# "Unknown models and new workflows"), as data: the same settings a
# configured family has (loaders, text encoder, VAE, sampling, prompt
# conventions, size range), written by the language model (FamilyWriter)
# from what the server reports, checked (Comfy::FamilyCheck), tried, and
# accepted by a person. Accepted, it joins the configured families
# (Comfy::Family.configured) and matches its model's name.
class LearnedFamily < ApplicationRecord
  include Learnable

  # Settings a family may have, as in config/comfy.yml `families`.
  KEYS = %w[text_encoder clip_type vae vae_override lora steps cfg sampler scheduler negative prefix negative_prefix
            prompt_style pixels multiple latent clip_skip].freeze

  validates :slug, presence: true, uniqueness: true
  validates :label, :model, presence: true

  # A new one for a model file, to be written by the language model.
  def self.for_model!(model, user:)
    stem = File.basename(model.to_s, ".*")
    create!(model: model, slug: "learned-#{stem.parameterize}", label: stem, match: [ stem.downcase ], user: user, status: "asking")
  end

  # { slug => family settings } for Comfy::Family: every one (so a proposed
  # one can be tried by name), or only those accepted (to match model names).
  # Remembered for a few seconds, since every recipe asks several times;
  # forgotten when one changes.
  def self.configs(accepted_only: false)
    @configs = nil if @configs_at && @configs_at < 5.seconds.ago
    @configs ||= begin
      @configs_at = Time.current
      all.map { |family| [ family.slug, family.config, family.accepted? ] }
    end
    @configs.filter_map { |slug, config, accepted| [ slug, config ] if accepted || !accepted_only }.to_h
  rescue ActiveRecord::StatementInvalid
    {} # before the table exists
  end

  def self.forget! = @configs = nil

  after_commit { self.class.forget! }

  def config = settings.to_h.slice(*KEYS).merge("label" => label, "match" => match)

  def check(capabilities) = Comfy::FamilyCheck.errors(settings, model: model, capabilities: capabilities)

  # A test render: the model with these settings and a plain prompt.
  def trial_graph(prompt:, seed:, prefix:, client:, capabilities:)
    family = Comfy::Family.new(slug, model)
    recipe = { "model" => model, "family" => slug, "loras" => [], "positive" => ArtDirection.join_prompt(family.prefix, prompt),
               "negative" => family.negative? ? family.negative_prefix : "", "width" => 1024, "height" => 1024, "transparent" => false }
    Comfy::Workflow.build(recipe, seed: seed, prefix: prefix, capabilities: capabilities)
  end
end
