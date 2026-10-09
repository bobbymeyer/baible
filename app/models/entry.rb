# frozen_string_literal: true

# One thing in the world, across every kind it's made in (docs/HANDOFF.md
# "Data model"): Cid, whose sprite, portrait and comic key art are each a
# subject of a different kind; the harbour town, as a location and a map.
# Its look (and LoRAs) is a layer of every image of it, between the kind's
# framing and the subject, kept word for word so it reads the same in every
# prompt. Its lore is the bible's text, and its notes the running talk about
# it (Note); neither ever goes in a prompt.
class Entry < ApplicationRecord
  belongs_to :project
  has_many :subjects, dependent: :nullify
  has_many :notes, -> { order(created_at: :desc, id: :desc) }, dependent: :destroy, inverse_of: :entry

  normalizes :name, :look, :lore, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: { scope: :project_id }

  def loras=(value)
    super(ArtDirection.loras(value))
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
