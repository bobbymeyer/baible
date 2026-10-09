# frozen_string_literal: true

# One generated image or piece of audio in a batch, with the seed that made it.
class Candidate < ApplicationRecord
  STATUSES = %w[queued running done failed].freeze

  belongs_to :batch
  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }

  # Each file refreshes the studios watching the subject as it lands.
  after_update_commit -> { batch.refresh_watchers }

  delegate :subject, :variant, to: :batch

  def finished?
    status.in?(%w[done failed])
  end

  def image? = file.attached? && file.content_type.to_s.start_with?("image/")
  def audio? = file.attached? && file.content_type.to_s.start_with?("audio/")

  def collect!(client)
    return unless comfy_prompt_id

    files = client.result(comfy_prompt_id)
    return if files.nil?
    return update!(status: "failed", error: "The workflow saved nothing") if files.empty?

    batch.audio? ? collect_audio!(client, files.first) : collect_image!(client, files)
  rescue Comfy::Unreachable
    raise # not this candidate's fault: the batch waits for ComfyUI (BatchJob)
  rescue Comfy::Error => e
    update!(status: "failed", error: e.message)
  end

  # Use this one: it becomes the target's current pick (the one before stays
  # in its history), and the batch is cleared.
  def pick!(user: nil)
    raise Refusal, "That candidate has nothing to pick yet" unless status == "done" && file.attached?

    pick = Pick.adopt!(self, user: user)
    batch.drafts&.destroy!
    batch.destroy!
    pick
  end

  private

  # Asked to lose its background: ComfyUI saved the cut-out and the
  # picture as rendered (Comfy::Workflow), and the cut-out is mended from
  # it (Cutout.keep_interior). Did the background come off? (A model can
  # leave it.)
  def collect_image!(client, images)
    cut, plain = Cutout.split(images)
    bytes = client.fetch(cut)
    wanted = batch.recipe["transparent"]
    bytes = Cutout.keep_interior(bytes, client.fetch(plain)) if wanted && plain
    file.attach(io: StringIO.new(bytes), filename: "#{subject.file_stem(variant, seed)}.png", content_type: "image/png")
    update!(status: "done", transparent: (Cutout.png_alpha?(bytes) if wanted), run_seconds: run_seconds_from(client))
  end

  # ComfyUI's file is what its name says (MP3, else FLAC).
  def collect_audio!(client, saved)
    extension = File.extname(saved["filename"].to_s).delete(".").presence || "flac"
    file.attach(io: StringIO.new(client.fetch(saved)), filename: "#{subject.file_stem(variant, seed)}.#{extension}",
                content_type: Marcel::MimeType.for(extension: extension), identify: false)
    update!(status: "done", run_seconds: run_seconds_from(client))
  end

  def run_seconds_from(client)
    client.respond_to?(:run_seconds) ? client.run_seconds(comfy_prompt_id) : nil
  end
end
