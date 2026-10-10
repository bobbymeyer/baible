# frozen_string_literal: true

# The thing being made (docs/HANDOFF.md "Data model"): a goblin, Cid, the
# harbour town, the harbour town's theme. Its own layer of the recipe is its
# name and notes, a model and LoRAs (an audio subject: notes as tags,
# lyrics and a length). Variants add a last, detail layer ("happy").
# It may be one depiction of an entry (Cid's portrait, of Cid), whose look
# comes before it in an image's recipe.
#
# It may derive from a subject of its kind's parent kind (docs/HANDOFF.md
# "Derived kinds and sheets"): Cid's portrait from Cid, the character.
# The parents' layers then come before its own (their words, models and
# LoRAs), it depicts the same entry, and its batches start from the
# parent's picture when its kind says so. Its own words are its notes: its
# name is a label, as the parent already names it. A sheet's subject lays
# out the picks of what derives from its parent (Sheet).
#
# A batch makes candidates for the subject itself or for one of its
# variants (the target), and the one picked is kept, with how it was made,
# as one of that target's Picks.
class Subject < ApplicationRecord
  belongs_to :project
  belongs_to :kind
  belongs_to :entry, optional: true
  belongs_to :parent, class_name: "Subject", optional: true
  has_many :derived_subjects, class_name: "Subject", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  has_many :variants, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :subject
  has_many :batches, dependent: :destroy
  has_many :picks, dependent: :destroy

  normalizes :name, :notes, :model, :lyrics, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: { scope: :kind_id }
  validates :seconds, numericality: { only_integer: true, in: Kind::SECONDS }, allow_nil: true
  validate :kind_in_project, :entry_in_project, :parent_fits

  before_validation { self.entry ||= parent.entry if parent }
  after_create :add_preset_variants

  delegate :image?, :audio?, :sheet?, :medium, to: :kind

  # The subjects it derives from, nearest first.
  def ancestors
    chain = []
    subject = parent
    while subject && chain.exclude?(subject) && subject != self
      chain << subject
      subject = subject.parent
    end
    chain
  end

  # The kinds a subject can derive from it in (Cid's: Portrait, Turnaround,
  # his design sheet), in the project's order.
  def derivable_kinds = project.kinds.select { |other| other.parent_kinds.include?(kind) }

  # What derives from it, at any depth, kind by kind in the project's order.
  def descendants
    derived_subjects.includes(:kind).sort_by { |subject| [ subject.kind.position, subject.kind.id, subject.name.downcase ] }
                    .flat_map { |subject| [ subject, *subject.descendants ] }
  end

  def loras=(value)
    super(ArtDirection.loras(value))
  end

  # What stands for the subject itself (variant nil) or a variant: its
  # canon pick, or its current one (docs/HANDOFF.md "Picks: history and
  # canon").
  def pick_for(variant = nil)
    target = target_picks(variant)
    target.find(&:canon?) || target.find(&:current?)
  end

  # Every pick of a target, newest first: its history.
  def target_picks(variant = nil)
    rows = picks.loaded? ? picks.select { |pick| pick.variant_id == variant&.id } : picks.where(variant_id: variant&.id).to_a
    rows.sort_by { |pick| [ pick.created_at, pick.id ] }.reverse
  end

  # How many of its targets (itself and each variant) have a pick.
  def picked_targets = picks.map(&:variant_id).uniq.size

  # The newest round for a target, if any.
  def batch_for(variant = nil)
    batches.where(variant: variant).order(:id).last
  end

  # --- the recipe ---------------------------------------------------------------

  # What the subject layer says: its name and notes for an image; its notes
  # (a description, as tags) for audio, where a name would only be noise.
  def subject_prompt
    audio? || parent ? notes.to_s : ArtDirection.join_prompt(name, notes)
  end

  # What its parents say, root first: Cid's words before his costume's.
  def parent_prompt = ArtDirection.join_prompt(*ancestors.reverse.map(&:subject_prompt))

  # The model from the lowest layer that names one. Audio doesn't use the
  # project's (an image model): ACE-Step's checkpoint is its default.
  def model_file
    if audio?
      ArtDirection.pick_model(model, kind.model, Comfy::Music.default_model)
    else
      ArtDirection.pick_model(model, kind.model, *ancestors.map(&:model), project.model, Comfy.config[:model])
    end
  end

  # What the entry layer says, for an image: the trigger of the LoRA it uses
  # (when that LoRA is on for this family), then its look. Audio has no
  # entry layer (a look isn't a sound); an audio subject joins an entry only
  # to sit on its page.
  def entry_prompt(family = image_family)
    entry && !audio? ? ArtDirection.join_prompt(entry.trained_trigger(family), entry.look) : ""
  end

  # The entry's LoRAs: the one it trained first, then any it names.
  def entry_loras(family = image_family)
    entry && !audio? ? [ entry.trained_lora(family), *entry.loras ].compact : []
  end

  # The LoRAs its parents name, root first (a character's own LoRA).
  def parent_loras = ArtDirection.stack_loras(*ancestors.reverse.map(&:loras))

  def image_family = Comfy::Family.for(model_file, capabilities: -> { Comfy.capabilities })

  # Where a batch for it starts when nobody chose (docs/HANDOFF.md "Derived
  # kinds and sheets"), as Batch.start!'s source with its denoise: a
  # variant redraws the subject's own picture, once it has one; the
  # subject redraws its parent's (or its head), as its kind says. nil:
  # from words alone.
  def derived_source(variant = nil)
    start = kind.derived_start or return
    own = pick_for(nil) if variant
    if own&.image?
      return { "pick_id" => own.id, "crop" => nil, "denoise" => Comfy.config.fetch(:chain, {}).fetch(:denoise, 0.45) }
    end

    from = parent&.pick_for(nil)
    start.merge("pick_id" => from.id) if from&.image?
  end

  # The layers as shown in the studio, top to bottom.
  def layers(variant = nil)
    top = audio? ? { "prompt" => project.sound, "model" => nil, "loras" => [] } : { "prompt" => project.style, "model" => project.model, "loras" => project.loras }
    rows = [
      top.merge("label" => project.name, "role" => "Project"),
      { "label" => kind.name, "role" => "Kind", "prompt" => kind.prompt, "model" => kind.model, "loras" => audio? ? [] : kind.loras }
    ]
    if entry && image?
      family = image_family
      rows << { "label" => entry.name, "role" => "Entry", "prompt" => entry_prompt(family), "model" => nil, "loras" => entry_loras(family) }
    end
    ancestors.reverse_each do |above|
      rows << { "label" => above.name, "role" => above.kind.name, "prompt" => above.subject_prompt, "model" => above.model, "loras" => above.loras }
    end
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
    return sheet_recipe if sheet?

    audio? ? audio_recipe(variant) : image_recipe(variant)
  end

  # A sheet's: what it lays out, frozen like any recipe (Sheet.plan).
  def sheet_recipe
    { "medium" => "sheet", "sheet" => Sheet.plan(self) }
  end

  def image_recipe(variant = nil)
    model = model_file
    family = Comfy::Family.for(model, capabilities: -> { Comfy.capabilities })
    parts = { "prefix" => family.prefix, "style" => project.style.to_s, "framing" => kind.prompt.to_s,
              "entry" => entry_prompt(family), "subject" => subject_prompt, "detail" => variant&.prompt.to_s }
    parts["parent"] = parent_prompt if parent
    width, height = family.size(kind.width, kind.height)
    {
      "medium" => "image",
      "model" => model,
      "family" => family.slug,
      "loras" => ArtDirection.stack_loras(project.loras, kind.loras, entry_loras(family), parent_loras, loras),
      "positive" => ArtDirection.compose(parts),
      "negative" => family.negative? ? ArtDirection.join_prompt(family.negative_prefix, project.negative, kind.negative) : "",
      "width" => width,
      "height" => height,
      "transparent" => kind.transparent,
      "parts" => parts
    }.merge(learned_workflow_part)
  end

  # A kind that makes its pictures with an accepted learned workflow puts its
  # graph in the recipe, frozen with the rest (docs/HANDOFF.md "Unknown
  # models and new workflows").
  def learned_workflow_part
    workflow = kind.learned_workflow
    return {} unless workflow&.accepted?

    { "learned_workflow" => { "id" => workflow.id, "name" => workflow.name, "graph" => workflow.graph } }
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

  # From a subject of its kind's parent kind (or of a kind derived from
  # that), never from itself or what derives from it.
  def parent_fits
    return unless parent && kind

    if parent == self || parent.ancestors.include?(self)
      errors.add(:parent, "can't be itself or derive from it")
    elsif parent.project_id != project_id || kind.parent_kinds.exclude?(parent.kind)
      errors.add(:parent, kind.parent ? "must be a #{kind.parent.name} (or derived from one)" : "needs a kind derived from another")
    end
  end

  def add_preset_variants
    kind.variant_presets.each_with_index do |preset, i|
      variants.find_or_create_by!(name: preset["name"]) { |variant| variant.assign_attributes(prompt: preset["prompt"], position: i) }
    end
  end
end
