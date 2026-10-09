# frozen_string_literal: true

# A world or setting, and the top layer of every recipe made in it
# (docs/HANDOFF.md "The layered recipe"): its house style for images, the
# negative prompt, a model and LoRAs, and its sound for audio. Everything
# below it (kinds, subjects, variants) is its own.
class Project < ApplicationRecord
  # Subjects first, so a kind isn't kept by its own subjects (Kind restricts).
  has_many :subjects, dependent: :destroy
  has_many :entries, -> { order(:name) }, dependent: :destroy, inverse_of: :project
  has_many :kinds, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :project
  has_many :picks, through: :subjects

  normalizes :name, :style, :negative, :model, :sound, :description, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: true

  def loras=(value)
    super(ArtDirection.loras(value))
  end

  # The kinds config/comfy.yml starts a project with (`kinds`).
  def add_starter_kinds!
    transaction do
      Kind.starters.each_with_index do |attrs, i|
        kinds.find_or_create_by!(name: attrs["name"]) { |kind| kind.assign_attributes(attrs.except("name").merge("position" => i)) }
      end
    end
  end
end
