# frozen_string_literal: true

# One thing in the world, across every kind it's made in (docs/HANDOFF.md
# "Data model"): Cid, whose sprite, portrait and comic key art are each a
# subject of a different kind; the harbour town, as a location and a map.
# Its look (and LoRAs) is a layer of every image of it, between the kind's
# framing and the subject, kept word for word so it reads the same in every
# prompt. Its lore is the bible's text, and its notes the running talk about
# it (Note); neither ever goes in a prompt.
#
# Its picks can train a LoRA (Training); the run it uses puts that LoRA, and
# the trigger it learned, at the head of its layer.
class Entry < ApplicationRecord
  belongs_to :project
  belongs_to :training, optional: true # the run whose LoRA it uses
  has_many :subjects, dependent: :nullify
  has_many :trainings, -> { order(version: :desc) }, dependent: :destroy, inverse_of: :entry
  has_many :notes, -> { order(created_at: :desc, id: :desc) }, dependent: :destroy, inverse_of: :entry

  normalizes :name, :look, :lore, with: ->(value) { value.to_s.strip.presence }
  normalizes :trigger, with: ->(value) { value.to_s.squish.presence }

  # Its runs go after it lets go of the one it uses (they point both ways).
  before_destroy { update_column(:training_id, nil) if training_id }

  validates :name, presence: true, uniqueness: { scope: :project_id }

  def loras=(value)
    super(ArtDirection.loras(value))
  end

  # The word its next LoRA learns to answer to: as set, or its name.
  def trigger_or_default = trigger || name.parameterize(separator: "_")

  # The LoRA it uses, for a recipe whose model is of the given family
  # (Comfy::Family): on at full strength when the model takes the LoRAs of
  # the one it was trained on (the same pool: SDXL, Pony, Illustrious),
  # else kept but switched off (docs/HANDOFF.md "The LoRA loop"). nil when
  # it uses none.
  def trained_lora(family)
    return unless training&.lora

    { "name" => training.lora, "strength" => 1.0, "on" => training.lora_pool == family.lora_pool }
  end

  # The trigger that leads its layer: the one its LoRA learned, while that
  # LoRA is on.
  def trained_trigger(family) = (training.trigger if trained_lora(family)&.fetch("on"))

  # Its image picks, every one of every subject, for a training set:
  # [[subject, variant, [pick, ...]], ...], each target's newest first.
  def pick_rows
    subjects_by_kind.values.flatten.select(&:image?).flat_map do |subject|
      [ nil, *subject.variants ].filter_map do |variant|
        picks = subject.target_picks(variant).select(&:image?)
        [ subject, variant, picks ] if picks.any?
      end
    end
  end

  # Its subjects, kind by kind in the project's order.
  def subjects_by_kind
    subjects.includes(:kind, :variants, picks: { file_attachment: :blob })
            .sort_by { |subject| [ subject.kind.position, subject.kind.id, subject.name.downcase ] }
            .group_by(&:kind)
  end

  # The picture that stands for it: the first image pick of its subjects.
  def cover
    subjects_by_kind.values.flatten.lazy.map { |subject| subject.pick_for(nil) }.find { |pick| pick&.image? }
  end
end
