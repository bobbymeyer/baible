# frozen_string_literal: true

# A kind of asset in a project, and the middle layer of its recipes
# (docs/HANDOFF.md "The layered recipe"): "Creature", "Portrait", "Map",
# "Music". Free-form, named by whoever runs the project. Its medium says
# what ComfyUI makes (an image or audio); an image kind frames the subject
# ("profile view, full body"), with its own negative prompt, size, model,
# LoRAs and whether the background comes off; an audio kind adds tags to
# the project's sound, and a length. Variant presets are the detail layers
# each new subject starts with (a portrait's expressions).
#
# A kind may derive from another (docs/HANDOFF.md "Derived kinds and
# sheets"): a Portrait, a Turnaround or a Battle sprite from a Character.
# Its subjects then derive from a subject of that kind (Cid's portrait from
# Cid), whose layer comes before theirs, and `derive` says whether their
# batches start from words alone or redraw the parent's picture (whole, or
# its head). A sheet kind makes no pictures of its own: each of its
# subjects lays the picks of what derives from its parent out as one
# picture (Sheet), from the kinds in `sheet_kind_ids` (all of them when
# empty).
class Kind < ApplicationRecord
  MEDIA = %w[image audio sheet].freeze
  DERIVE = {
    "words" => "Its words only",
    "picture" => "Redraw its picture",
    "head" => "Redraw its head"
  }.freeze
  SIZES = (256..2048)
  SECONDS = (10..240)

  belongs_to :project
  # An accepted learned workflow it makes its pictures with, instead of the
  # builder's graph (docs/HANDOFF.md "Unknown models and new workflows").
  belongs_to :learned_workflow, optional: true
  belongs_to :parent, class_name: "Kind", optional: true
  has_many :derived_kinds, -> { order(:position, :id) }, class_name: "Kind", foreign_key: :parent_id,
           dependent: :restrict_with_error, inverse_of: :parent
  has_many :subjects, dependent: :restrict_with_error
  has_many :standing_orders, dependent: :destroy

  normalizes :name, :prompt, :negative, :model, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: { scope: :project_id }
  validates :medium, inclusion: { in: MEDIA }
  validates :width, :height, numericality: { only_integer: true, in: SIZES }
  validates :seconds, numericality: { only_integer: true, in: SECONDS }
  validates :derive, inclusion: { in: DERIVE.keys }
  validates :derive_denoise, numericality: { in: 0.1..1.0 }, allow_nil: true
  validate :learned_workflow_is_accepted, if: :learned_workflow_id_changed?
  validate :parent_fits

  # From config/comfy.yml `kinds`, as attributes.
  def self.starters
    Array(Comfy.config[:kinds]).map do |row|
      row = row.to_h.deep_stringify_keys
      presets = row.delete("variants").to_h.map { |name, words| { "name" => name.to_s, "prompt" => words.to_s } }
      row.slice("name", "medium", "prompt", "negative", "width", "height", "transparent", "seconds", "derive", "derive_denoise", "from", "sheet_of")
         .merge("variant_presets" => presets)
    end
  end

  def image? = medium == "image"
  def audio? = medium == "audio"
  def sheet? = medium == "sheet"

  # The kinds it derives from, nearest first.
  def ancestors
    chain = []
    kind = parent
    while kind && chain.exclude?(kind) && kind != self
      chain << kind
      kind = kind.parent
    end
    chain
  end

  # It and every kind derived from it, at any depth, in the project's order.
  def lineage
    project.kinds.select { |kind| kind == self || kind.ancestors.include?(self) }
  end

  # The kinds a subject of this one can derive from: its parent kind, or any
  # kind derived from that (a costume's portrait derives from the costume),
  # but never itself, what derives from it, or a sheet.
  def parent_kinds
    parent ? parent.lineage.reject(&:sheet?) - lineage : []
  end

  # A sheet's kinds, in the project's order: as chosen, or every kind that
  # derives from its parent's.
  def sheet_kinds
    return [] unless sheet? && parent

    kinds = parent.lineage.reject(&:sheet?)
    sheet_kind_ids.present? ? kinds.select { |kind| sheet_kind_ids.map(&:to_i).include?(kind.id) } : kinds
  end

  def sheet_kind_ids=(value)
    super(Array(value).compact_blank.map(&:to_i).uniq)
  end

  # How its subjects' batches start from their parent's picture: nil for
  # words alone, else { "crop", "denoise" } (config/comfy.yml `chain` when
  # it names no denoise of its own).
  def derived_start
    return if derive == "words" || !image?

    chain = Comfy.config.fetch(:chain, {})
    crop = derive == "head" ? "head" : nil
    { "crop" => crop, "denoise" => derive_denoise || (crop ? chain.fetch(:head_denoise, 0.55) : chain.fetch(:denoise, 0.45)) }
  end

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

  private

  def parent_fits
    return errors.add(:parent, "is needed for a sheet: the kind its subjects lay out") if sheet? && !parent
    return unless parent

    errors.add(:parent, "must be one of the project's") if parent.project_id != project_id
    errors.add(:parent, "can't be itself or derive from it") if parent == self || (persisted? && parent.ancestors.include?(self))
    errors.add(:parent, "must be an image kind") unless parent.image?
    errors.add(:medium, "can't be audio for a derived kind") if audio?
  end

  def learned_workflow_is_accepted
    errors.add(:learned_workflow, "must be one a person has accepted") if learned_workflow && !learned_workflow.accepted?
  end
end
