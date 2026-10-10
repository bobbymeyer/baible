# frozen_string_literal: true

# A world or setting, and the top layer of every recipe made in it
# (docs/HANDOFF.md "The layered recipe"): its house style for images, the
# negative prompt, a model and LoRAs, and its sound for audio. Everything
# below it (kinds, subjects, variants) is its own.
class Project < ApplicationRecord
  # Subjects first, so a kind isn't kept by its own subjects (Kind restricts).
  has_many :subjects, dependent: :destroy
  has_many :entries, -> { order(:name) }, dependent: :destroy, inverse_of: :project
  has_many :standing_orders, dependent: :destroy
  # Kinds go all at once: none is kept by those derived from it (Kind restricts).
  before_destroy { kinds.update_all(parent_id: nil) }
  has_many :kinds, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :project
  has_many :picks, through: :subjects

  normalizes :name, :style, :negative, :model, :sound, :description, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: true

  def loras=(value)
    super(ArtDirection.loras(value))
  end

  # The kinds config/comfy.yml starts a project with (`kinds`). A kind
  # derives from one named before it (`from`); a sheet lays out the kinds it
  # names (`sheet_of`), or all that derive from its parent.
  def add_starter_kinds!
    transaction do
      Kind.starters.each_with_index do |attrs, i|
        kinds.find_or_create_by!(name: attrs["name"]) do |kind|
          kind.assign_attributes(attrs.except("name", "from", "sheet_of").merge("position" => i))
          kind.parent = kinds.find_by(name: attrs["from"]) if attrs["from"]
          kind.sheet_kind_ids = kinds.where(name: Array(attrs["sheet_of"])).pluck(:id)
        end
      end
    end
  end
end
