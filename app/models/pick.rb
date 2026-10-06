# frozen_string_literal: true

# The chosen file for a subject or one of its variants (docs/HANDOFF.md
# "Batches, candidates, picks"), with how it was made: the seed, the prompt
# and the full recipe, including the workflow's outline. One per target;
# picking again replaces it. It is what leaves baible: downloaded with its
# sidecar (#sidecar, docs/HANDOFF.md "Export"), and a batch can start from
# it (a chain).
class Pick < ApplicationRecord
  # The sidecar's format; bump it when a field changes meaning or goes.
  SIDECAR_VERSION = 1

  belongs_to :subject
  belongs_to :variant, optional: true
  has_one_attached :file

  validates :variant_id, uniqueness: { scope: :subject_id }
  validate :variant_is_the_subjects

  scope :images, -> { joins(file_attachment: :blob).where("active_storage_blobs.content_type LIKE 'image/%'") }

  # A candidate's file and how it was made, as its target's pick.
  def self.adopt!(candidate)
    batch = candidate.batch
    pick = find_or_initialize_by(subject: batch.subject, variant: batch.variant)
    transaction do
      pick.file.attach(io: StringIO.new(candidate.file.download), filename: candidate.file.filename.to_s,
                       content_type: candidate.file.content_type, identify: false)
      pick.update!(seed: candidate.seed, prompt: batch.recipe["positive"], recipe: batch.recipe, run_seconds: candidate.run_seconds)
    end
    pick
  end

  def image? = file.attached? && file.content_type.to_s.start_with?("image/")
  def audio? = file.attached? && file.content_type.to_s.start_with?("audio/")

  def medium = recipe["medium"] || (audio? ? "audio" : "image")

  def title = subject.title(variant)

  def filename = file.filename.to_s

  def sidecar_filename = "#{File.basename(filename, '.*')}.json"

  # How it was made, for whoever uses the file next (docs/HANDOFF.md
  # "Export"): what it is, where it sits in the project, and everything
  # needed to make it again. Every key is always there; what doesn't apply
  # (an image's lyrics, audio's size) is null.
  def sidecar
    kind = subject.kind
    {
      "baible" => SIDECAR_VERSION,
      "file" => filename,
      "content_type" => file.content_type,
      "byte_size" => file.byte_size,
      "sha256" => (Digest::SHA256.hexdigest(file.download) if file.attached?),
      "medium" => medium,
      "project" => subject.project.name,
      "kind" => kind.name,
      "subject" => subject.name,
      "variant" => variant&.name,
      "seed" => seed,
      "prompt" => prompt,
      "negative" => recipe["negative"].presence,
      "model" => recipe["model"],
      "family" => recipe["family"],
      "loras" => ArtDirection.active_loras(ArtDirection.loras(recipe["loras"])),
      "width" => recipe["width"],
      "height" => recipe["height"],
      "transparent" => recipe["transparent"],
      "lyrics" => recipe["lyrics"].presence,
      "seconds" => recipe["seconds"],
      "source" => recipe["source"]&.slice("label", "crop")&.merge("denoise" => recipe["denoise"]),
      "workflow" => recipe["workflow"],
      "run_seconds" => run_seconds,
      "picked_at" => updated_at&.utc&.iso8601,
      "recipe" => recipe
    }
  end

  private

  def variant_is_the_subjects
    errors.add(:variant, "must be the subject's own") if variant && variant.subject_id != subject_id
  end
end
