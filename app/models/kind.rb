# frozen_string_literal: true

# A kind of asset in a project, and the middle layer of its recipes
# (docs/HANDOFF.md "The layered recipe"): "Creature", "Portrait", "Map",
# "Music". Free-form, named by whoever runs the project. Its medium says
# what ComfyUI makes (an image or audio); an image kind frames the subject
# ("profile view, full body"), with its own negative prompt, size, model,
# LoRAs and whether the background comes off; an audio kind adds tags to
# the project's sound, and a length. Variant presets are the detail layers
# each new subject starts with (a portrait's expressions).
class Kind < ApplicationRecord
  MEDIA = %w[image audio].freeze
  SIZES = (256..2048)
  SECONDS = (10..240)

  belongs_to :project
  has_many :subjects, dependent: :restrict_with_error
  has_many :standing_orders, dependent: :destroy

  normalizes :name, :prompt, :negative, :model, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: { scope: :project_id }
  validates :medium, inclusion: { in: MEDIA }
  validates :width, :height, numericality: { only_integer: true, in: SIZES }
  validates :seconds, numericality: { only_integer: true, in: SECONDS }

  # From config/comfy.yml `kinds`, as attributes.
  def self.starters
    Array(Comfy.config[:kinds]).map do |row|
      row = row.to_h.deep_stringify_keys
      presets = row.delete("variants").to_h.map { |name, words| { "name" => name.to_s, "prompt" => words.to_s } }
      row.slice("name", "medium", "prompt", "negative", "width", "height", "transparent", "seconds").merge("variant_presets" => presets)
    end
  end

  def image? = medium == "image"
  def audio? = medium == "audio"

  def loras=(value)
    super(ArtDirection.loras(value))
  end

  # Presets from a form: rows of { "name", "prompt" }, or text with one
  # "name: words" a line.
  def variant_presets=(value)
    rows = if value.is_a?(String)
      value.lines.filter_map do |line|
        name, words = line.split(":", 2).map(&:strip)
        { "name" => name, "prompt" => words.to_s } if name.present?
      end
    else
      (value.is_a?(Hash) ? value.values : Array(value)).map { |row| row.to_h.stringify_keys.slice("name", "prompt") }
    end
    super(rows.reject { |row| row["name"].to_s.strip.empty? }.uniq { |row| row["name"] })
  end

  # The presets as text, for the form.
  def variant_presets_text
    variant_presets.map { |row| "#{row['name']}: #{row['prompt']}" }.join("\n")
  end

  def label = "#{name} (#{medium})"
end
