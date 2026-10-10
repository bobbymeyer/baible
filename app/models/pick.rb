# frozen_string_literal: true

# A chosen file for a subject or one of its variants (docs/HANDOFF.md
# "Picks: history and canon"), with how it was made: the seed, the prompt
# and the full recipe, including the workflow's outline, and who picked it.
#
# Picks are kept. A target has a history: the newest pick is its current
# one, and at most one is canon, approved by someone. What stands for the
# target (#standing) is its canon pick, or its current one. It is what
# leaves baible: downloaded with its sidecar (#sidecar, docs/HANDOFF.md
# "Export"), and a batch can start from it (a chain).
class Pick < ApplicationRecord
  # The sidecar's format; bump it when a field changes meaning or goes.
  SIDECAR_VERSION = 1

  belongs_to :subject
  belongs_to :variant, optional: true
  belongs_to :user, optional: true
  belongs_to :canon_by, class_name: "User", optional: true
  has_one_attached :file

  validate :variant_is_the_subjects

  scope :images, -> { joins(file_attachment: :blob).where("active_storage_blobs.content_type LIKE 'image/%'") }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :of_target, ->(subject, variant) { where(subject: subject, variant: variant) }

  # What stands for each target: its canon pick, or its current one when
  # nothing is canon. picks: a target's picks, or several targets'.
  def self.standing(picks)
    picks.group_by { |pick| [ pick.subject_id, pick.variant_id ] }
         .filter_map { |_, rows| rows.find(&:canon?) || rows.find(&:current?) }
  end

  # A candidate's file and how it was made, as its target's new current
  # pick. The pick before it stays, in the history; canon stays canon.
  def self.adopt!(candidate, user: nil)
    batch = candidate.batch
    transaction do
      of_target(batch.subject, batch.variant).where(current: true).update_all(current: false, updated_at: Time.current)
      new(subject: batch.subject, variant: batch.variant, user: user, current: true, seed: candidate.seed,
          prompt: batch.recipe["positive"], recipe: batch.recipe, run_seconds: candidate.run_seconds).tap do |pick|
        pick.file.attach(io: StringIO.new(candidate.file.download), filename: candidate.file.filename.to_s,
                         content_type: candidate.file.content_type, identify: false)
        pick.save!
      end
    end
  end

  def canon? = canon_at.present?

  # The other picks of the same target, newest first.
  def target_picks = Pick.of_target(subject_id, variant_id).newest_first

  # Use this again: it becomes its target's current pick.
  def make_current!
    transaction do
      target_picks.where(current: true).where.not(id: id).update_all(current: false, updated_at: Time.current)
      update!(current: true)
    end
  end

  # Approve it as its target's canon, in place of any other.
  def approve!(user)
    transaction do
      target_picks.where.not(canon_at: nil).where.not(id: id).update_all(canon_at: nil, canon_by_id: nil, updated_at: Time.current)
      update!(canon_at: Time.current, canon_by: user)
    end
  end

  def unapprove!
    update!(canon_at: nil, canon_by: nil)
  end

  # Let it go from the history. Canon is unapproved first, on purpose. When
  # it was current, the newest pick left takes its place.
  def let_go!
    raise Refusal, "#{title}'s canon pick can't be let go: unapprove it first" if canon?
    raise Refusal, "This pick of #{title} trained a LoRA, so it stays with that run's record" if Training.using?(self)

    transaction do
      destroy!
      target_picks.first&.update!(current: true) if current?
    end
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
      "entry" => subject.entry&.name,
      "subject" => subject.name,
      "variant" => variant&.name,
      "picked_by" => user&.email_address,
      "canon" => canon?,
      "canon_by" => canon_by&.email_address,
      "canon_at" => canon_at&.utc&.iso8601,
      "seed" => (seed unless medium == "sheet"),
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
      "picked_at" => created_at&.utc&.iso8601,
      "recipe" => recipe
    }
  end

  private

  def variant_is_the_subjects
    errors.add(:variant, "must be the subject's own") if variant && variant.subject_id != subject_id
  end
end
