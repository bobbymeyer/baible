# frozen_string_literal: true

require "rubygems/package"

# One LoRA training run for an entry (docs/HANDOFF.md "The LoRA loop"):
# a set of its picks with a caption each, a base model, the trigger the
# LoRA learns to answer to, and the settings, all frozen when it starts,
# like a recipe. A set can be kept without training it ("set"), to train
# later or to download for a trainer elsewhere (#tar).
#
# A run uploads its pictures and captions into ComfyUI's inputs, queues the
# graph Comfy::Training builds, and is polled like a batch (TrainingJob,
# ComfyRun) until ComfyUI has saved the LoRA. The entry then uses it.
class Training < ApplicationRecord
  include ComfyRun

  STATUSES = [ "set", *ComfyRun::STATUSES ].freeze
  SETTINGS = %w[steps rank learning_rate batch_size].freeze

  belongs_to :entry
  belongs_to :user, optional: true

  normalizes :trigger, with: ->(value) { value.to_s.squish.presence }

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, :model, :family, presence: true
  validates :version, uniqueness: { scope: :entry_id }
  validate :has_items

  before_destroy { entry.update!(training: nil) if entry.training_id == id }
  after_update_commit :refresh_watchers

  # What a caption says about a pick: the trigger, then the house style, the
  # framing, the subject (as the language model wrote it, if it did) and the
  # detail, from the pick's recipe, but not the entry's look (what the LoRA
  # should learn to tie to the trigger) and not the family's quality words.
  # Without the trigger, which the run puts first: the form shows this.
  def self.caption_for(pick)
    parts = pick.recipe["parts"]
    return pick.prompt.to_s unless parts.is_a?(Hash)

    ArtDirection.join_prompt(parts["style"], parts["framing"], parts["written"].presence || parts["subject"], parts["detail"])
  end

  # A new set for an entry. rows: [{ pick:, caption: }] in order; captions
  # are kept as written, the trigger put first. train: queue it now.
  def self.start!(entry, rows, trigger:, model:, settings:, user:, train:)
    family = Comfy::Family.for(model, capabilities: -> { Comfy.capabilities })
    settings = family.training.merge(settings.to_h.stringify_keys.slice(*SETTINGS).compact_blank)
                         .to_h { |key, value| [ key, key == "learning_rate" ? value.to_f : value.to_i ] }
    items = rows.each_with_index.map do |row, i|
      pick = row.fetch(:pick)
      { "pick_id" => pick.id, "title" => pick.title, "seed" => pick.seed, "sha256" => Digest::SHA256.hexdigest(pick.file.download),
        "file" => format("%03d.png", i + 1), "caption" => ArtDirection.join_prompt(trigger, row[:caption]) }
    end
    training = transaction do
      entry.update!(trigger: trigger)
      entry.trainings.create!(version: entry.trainings.maximum(:version).to_i + 1, trigger: trigger, model: model, family: family.slug,
                              settings: settings, items: items, user: user, status: "set")
    end
    training.train! if train
    training
  end

  # The picks a run used: they can't be let go (Pick#let_go!).
  def self.using?(pick)
    where("EXISTS (SELECT 1 FROM json_each(trainings.items) WHERE json_extract(json_each.value, '$.pick_id') = ?)", pick.id).exists?
  end

  # Queue a kept set (or a failed run) for ComfyUI.
  def train!
    raise Refusal, "Only a kept set or a failed run can be trained" unless status.in?(%w[set failed])

    update!(status: "queued", error: nil, comfy_prompt_id: nil, submitted_at: nil, lora: nil, workflow: nil)
    TrainingJob.perform_later(self)
  end

  def title = "#{entry.name} v#{version}"

  # The LoRAs it is one of (Comfy::Family#lora_pool), from its base model.
  def lora_pool = Comfy::Family.new(family, model).lora_pool

  # What its files are called: the-drowned-coast-cid-v1.
  def stem = [ entry.project.name.parameterize, entry.name.parameterize, "v#{version}" ].join("-")

  # Where its set goes in ComfyUI's inputs, and where SaveLoRA puts the LoRA
  # in ComfyUI's outputs. ComfyUI lists it as baible/<stem>_00001_.safetensors
  # once its output/loras folder is one of its LoRA folders (README).
  def folder = "baible/train/#{stem}"
  def prefix = "loras/baible/#{stem}"
  def expected_lora = "baible/#{stem}_00001_.safetensors"

  # Training takes hours, not minutes (config/comfy.yml `training.timeout`).
  def run_timeout = Comfy.config.dig(:training, :timeout).to_i.nonzero?&.seconds || 6.hours

  def comfy_started_at = submitted_at || updated_at

  # Its pictures as a run uploads them: flattened on white, since ComfyUI's
  # dataset loader drops alpha, and a cut-out's hidden pixels are no
  # background to learn.
  def picture(item)
    pick = Pick.find_by(id: item["pick_id"])
    raise Comfy::Error, "#{item['title']} (seed #{item['seed']}) is gone from baible" unless pick&.file&.attached?

    Cutout.on_white(pick.file.download)
  end

  # Put the set in ComfyUI's inputs: each picture with its caption beside it.
  def upload_set!(client)
    items.each do |item|
      client.upload(picture(item), item["file"], subfolder: folder)
      client.upload(item["caption"], item["file"].sub(/\.png\z/, ".txt"), subfolder: folder, content_type: "text/plain")
    end
  end

  def submit!(client)
    capabilities = client.capabilities
    unless capabilities.reachable?
      raise (capabilities.offline? ? Comfy::Unreachable : Comfy::Error), capabilities.error || "ComfyUI isn't answering"
    end

    graph = Comfy::Training.build(model: model, family: family, folder: folder, prefix: prefix, settings: settings,
                                  seed: Random.rand(2**31), capabilities: capabilities)
    update!(workflow: Comfy::Workflow.outline(graph), comfy_prompt_id: client.submit(graph), status: "running", error: nil,
            submitted_at: Time.current)
  end

  # Done once ComfyUI's history says so (SaveLoRA saves nothing it lists);
  # an error there fails it (ApplicationJob#poll_comfy). The entry then uses
  # its LoRA, as ComfyUI lists it, or as it will once it can see it.
  def collect!(client)
    return false if client.result(comfy_prompt_id).nil?

    listed = client.capabilities.loras.find { |file| File.basename(file).start_with?("#{stem}_") }
    transaction do
      update!(status: "done", lora: listed || expected_lora, run_seconds: client.run_seconds(comfy_prompt_id))
      entry.update!(training: self)
    end
    true
  end

  # Whether ComfyUI lists its LoRA, for the pages.
  def listed?(capabilities) = lora.present? && capabilities.reachable? && capabilities.find(capabilities.loras, lora).present?

  # The set for a trainer elsewhere, in the kohya layout: <stem>/1_<trigger>/
  # with each picture and its caption (.txt) beside it, as a tar archive.
  def tar
    io = StringIO.new("".b)
    dir = "#{stem}/1_#{trigger.parameterize(separator: '_')}"
    Gem::Package::TarWriter.new(io) do |archive|
      items.each do |item|
        bytes = picture(item)
        archive.add_file_simple("#{dir}/#{item['file']}", 0o644, bytes.bytesize) { |file| file.write(bytes) }
        caption = item["caption"].to_s.b
        archive.add_file_simple("#{dir}/#{item['file'].sub(/\.png\z/, '.txt')}", 0o644, caption.bytesize) { |file| file.write(caption) }
      end
    end
    io.string
  end

  # The entry's page follows its runs (TrainingsController#index reloads
  # the "trainings" frame).
  def refresh_watchers
    Turbo::StreamsChannel.broadcast_action_to(entry, :trainings, action: :reload_frame, target: "trainings")
  end

  private

  def has_items
    errors.add(:items, "need at least one picture") if items.blank?
  end
end
