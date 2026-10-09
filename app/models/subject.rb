# frozen_string_literal: true

# The thing being made (docs/HANDOFF.md "Data model"): a goblin, Cid, the
# harbour town, the harbour town's theme. Its own layer of the recipe is its
# name and notes, a model and LoRAs (an audio subject: notes as tags,
# lyrics and a length). Variants add a last, detail layer ("happy").
# It may be one depiction of an entry (Cid's portrait, of Cid), whose look
# comes before it in an image's recipe.
#
# A batch makes candidates for the subject itself or for one of its
# variants (the target), and the one picked is kept, with how it was made,
# as that target's Pick.
class Subject < ApplicationRecord
  belongs_to :project
  belongs_to :kind
  belongs_to :entry, optional: true
  has_many :variants, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :subject
  has_many :batches, dependent: :destroy
  has_many :picks, dependent: :destroy

  normalizes :name, :notes, :model, :lyrics, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: { scope: :kind_id }
  validates :seconds, numericality: { only_integer: true, in: Kind::SECONDS }, allow_nil: true
  validate :kind_in_project, :entry_in_project

  after_create :add_preset_variants

  delegate :image?, :audio?, :medium, to: :kind

  def loras=(value)
    super(ArtDirection.loras(value))
  end

  # The pick for the subject itself (variant nil) or a variant.
  def pick_for(variant = nil)
    picks.loaded? ? picks.find { |pick| pick.variant_id == variant&.id } : picks.find_by(variant_id: variant&.id)
  end

  # The newest round for a target, if any.
  def batch_for(variant = nil)
    batches.where(variant: variant).order(:id).last
  end

  # --- the recipe ---------------------------------------------------------------

  # What the subject layer says: its name and notes for an image; its notes
  # (a description, as tags) for audio, where a name would only be noise.
  def subject_prompt
    audio? ? notes.to_s : ArtDirection.join_prompt(name, notes)
  end

  # The model from the lowest layer that names one. Audio doesn't use the
  # project's (an image model): ACE-Step's checkpoint is its default.
  def model_file
    if audio?
      ArtDirection.pick_model(model, kind.model, Comfy::Music.default_model)
    else
      ArtDirection.pick_model(model, kind.model, project.model, Comfy.config[:model])
    end
  end

  # What the entry layer says: its look, for an image. Audio has no entry
  # layer (a look isn't a sound); an audio subject joins an entry only to
  # sit on its page.
  def entry_prompt
    entry && !audio? ? entry.look.to_s : ""
  end

  def entry_loras
    entry && !audio? ? entry.loras : []
  end

  # The layers as shown in the studio, top to bottom.
  def layers(variant = nil)
    top = audio? ? { "prompt" => project.sound, "model" => nil, "loras" => [] } : { "prompt" => project.style, "model" => project.model, "loras" => project.loras }
    rows = [
      top.merge("label" => project.name, "role" => "Project"),
      { "label" => kind.name, "role" => "Kind", "prompt" => kind.prompt, "model" => kind.model, "loras" => audio? ? [] : kind.loras }
    ]
    rows << { "label" => entry.name, "role" => "Entry", "prompt" => entry_prompt, "model" => nil, "loras" => entry_loras } if entry && image?
    rows << { "label" => name, "role" => "Subject", "prompt" => subject_prompt, "model" => model, "loras" => audio? ? [] : loras }
    rows << { "label" => variant.name, "role" => "Variant", "prompt" => variant.prompt, "loras" => [] } if variant
    rows
  end

  # Everything ComfyUI needs apart from the seed (docs/HANDOFF.md "The
  # layered recipe"). For an image, the family of the model decides the
  # quality words that lead the prompt, whether there is a negative prompt
  # at all, and the size (scaled into its trained range). The parts are
  # kept so the subject can be rewritten (PromptWriter) and the prompt put
  # back together.
  def recipe(variant = nil)
    audio? ? audio_recipe(variant) : image_recipe(variant)
  end

  def image_recipe(variant = nil)
    model = model_file
    family = Comfy::Family.for(model, capabilities: -> { Comfy.capabilities })
    parts = { "prefix" => family.prefix, "style" => project.style.to_s, "framing" => kind.prompt.to_s,
              "entry" => entry_prompt, "subject" => subject_prompt, "detail" => variant&.prompt.to_s }
    width, height = family.size(kind.width, kind.height)
    {
      "medium" => "image",
      "model" => model,
      "family" => family.slug,
      "loras" => ArtDirection.stack_loras(project.loras, kind.loras, entry_loras, loras),
      "positive" => ArtDirection.compose(parts),
      "negative" => family.negative? ? ArtDirection.join_prompt(family.negative_prefix, project.negative, kind.negative) : "",
      "width" => width,
      "height" => height,
      "transparent" => kind.transparent,
      "parts" => parts
    }
  end

  def audio_recipe(variant = nil)
    parts = { "style" => project.sound.to_s, "framing" => kind.prompt.to_s, "subject" => subject_prompt, "detail" => variant&.prompt.to_s }
    {
      "medium" => "audio",
      "model" => model_file,
      "positive" => ArtDirection.compose(parts),
      "lyrics" => lyrics.to_s,
      "seconds" => seconds || kind.seconds,
      "parts" => parts
    }
  end

  # A seed to try first, for a consistent look: a variant starts from the
  # subject's own pick's seed, so a face stays closer across expressions.
  def seed_hint(variant = nil)
    pick_for(nil)&.seed if variant
  end

  # What a target's files are called: goblin-123.png, cid-happy-123.png.
  def file_stem(variant, seed)
    [ name.parameterize.presence || "subject-#{id}", variant&.name&.parameterize.presence, seed ].compact.join("-")
  end

  # A target's name in a sentence ("Cid", "Cid, happy").
  def title(variant = nil)
    variant ? "#{name}, #{variant.name}" : name
  end

  private

  def kind_in_project
    errors.add(:kind, "must be one of the project's") if kind && project && kind.project_id != project_id
  end

  def entry_in_project
    errors.add(:entry, "must be one of the project's") if entry && project && entry.project_id != project_id
  end

  def add_preset_variants
    kind.variant_presets.each_with_index do |preset, i|
      variants.find_or_create_by!(name: preset["name"]) { |variant| variant.assign_attributes(prompt: preset["prompt"], position: i) }
    end
  end
end
