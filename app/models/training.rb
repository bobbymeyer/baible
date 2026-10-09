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

  # "set": kept, not trained. "scheduled": to train in the night window
  # (NightShift), after the night's generations.
  STATUSES = [ "set", "scheduled", *ComfyRun::STATUSES ].freeze
  SETTINGS = %w[steps rank learning_rate batch_size].freeze

  HOSTS = %w[local remote].freeze

  belongs_to :entry
  belongs_to :user, optional: true
  # The LoRA, fetched back from the ComfyUI that trained it.
  has_one_attached :lora_file

  normalizes :trigger, with: ->(value) { value.to_s.squish.presence }

  validates :status, inclusion: { in: STATUSES }
  validates :host, inclusion: { in: HOSTS }
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
  # are kept as written, the trigger put first. train: :now to queue it,
  # :tonight to schedule it for the night window, nil to keep it. host:
  # "remote" for the training host, "local" for this ComfyUI; by default
  # the training host when there is one.
  def self.start!(entry, rows, trigger:, model:, settings:, user:, train:, host: nil)
    host = host.presence_in(HOSTS) || (Comfy.training_host? ? "remote" : "local")
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
                              settings: settings, items: items, user: user, status: "set", host: host)
    end
    case train
    when :now then training.train!
    when :tonight then training.schedule!
    end
    training
  end

  # The picks a run used: they can't be let go (Pick#let_go!).
  def self.using?(pick)
    where("EXISTS (SELECT 1 FROM json_each(trainings.items) WHERE json_extract(json_each.value, '$.pick_id') = ?)", pick.id).exists?
  end

  # Queue a kept set, a failed run or a scheduled one (the night shift) for
  # ComfyUI.
  def train!
    raise Refusal, "Only a kept set or a failed run can be trained" unless status.in?(%w[set failed scheduled])

    update!(status: "queued", error: nil, comfy_prompt_id: nil, submitted_at: nil, lora: nil, workflow: nil,
            host_started_at: nil, host_note: nil)
    TrainingJob.perform_later(self)
  end

  # To train in the night window (NightShift), or not after all.
  def schedule!
    raise Refusal, "Only a kept set or a failed run can be scheduled" unless status.in?(%w[set failed])

    update!(status: "scheduled", error: nil)
  end

  def unschedule!
    raise Refusal, "#{title} isn't scheduled" unless status == "scheduled"

    update!(status: "set")
  end

  def title = "#{entry.name} v#{version}"

  def remote? = host == "remote"

  # The ComfyUI it trains on (Comfy.client_for).
  def client = Comfy.client_for(host)

  # --- the training host -------------------------------------------------

  # A rented pod (RunPod), started once for the run. A refusal from RunPod
  # (a wrong key or pod) fails the run with its reason; RunPod out of reach
  # is waited for, as ComfyUI is.
  def start_host!
    return unless remote? && RunPod.enabled? && host_started_at.nil?

    RunPod.start!
    update!(host_started_at: Time.current)
  rescue RunPod::Unreachable => e
    raise Comfy::Unreachable, e.message
  rescue RunPod::Error => e
    raise Comfy::Error, "RunPod wouldn't start the pod: #{e.message}"
  end

  # Stop the pod it started, whatever became of the run. A pod left running
  # costs money, so not stopping it is said loudly (host_note, the morning
  # summary) rather than raised.
  def stop_host!
    return unless remote? && host_started_at && RunPod.enabled?

    RunPod.stop!
    update!(host_started_at: nil)
  rescue RunPod::Error => e
    update!(host_note: "RunPod didn't stop pod #{RunPod.pod_id} (#{e.message}): stop it by hand, it's costing money.")
  end

  # Still booting: a pod started a few minutes ago whose ComfyUI isn't up
  # yet answers through RunPod's proxy with errors, which mean "wait" here.
  def booting?
    remote? && host_started_at.present? && host_started_at > Comfy.training_host.fetch(:boot_minutes, 20).to_i.minutes.ago
  end

  def fail!(message)
    super
    stop_host!
  end

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

  # Upload the set and queue the graph, once ComfyUI answers.
  def submit!(client)
    capabilities = client.capabilities
    unless capabilities.reachable?
      if capabilities.offline? || booting?
        raise Comfy::Unreachable, "#{remote? ? 'The training host' : 'ComfyUI'} isn't up yet: #{capabilities.error}"
      end

      raise Comfy::Error, capabilities.error || "ComfyUI isn't answering"
    end

    upload_set!(client)
    graph = Comfy::Training.build(model: model, family: family, folder: folder, prefix: prefix, settings: settings,
                                  seed: Random.rand(2**31), capabilities: capabilities)
    update!(workflow: Comfy::Workflow.outline(graph), comfy_prompt_id: client.submit(graph), status: "running", error: nil,
            submitted_at: Time.current)
  end

  # Done once ComfyUI's history says so (SaveLoRA saves nothing it lists);
  # an error there fails it (ApplicationJob#poll_comfy). The LoRA is fetched
  # back from that ComfyUI's outputs and kept (lora_file), put where this
  # ComfyUI reads LoRAs when baible can (config/comfy.yml `trained_loras`),
  # and the entry then uses it. The pod, if one was started, is stopped.
  def collect!(client)
    return false if client.result(comfy_prompt_id).nil?

    bytes = fetch_lora(client)
    lora_file.attach(io: StringIO.new(bytes), filename: "#{stem}.safetensors", content_type: "application/octet-stream", identify: false) if bytes
    name = (bytes && install(bytes)) || (remote? ? installed_name : local_name(client))
    transaction do
      update!(status: "done", lora: name, run_seconds: client.run_seconds(comfy_prompt_id))
      entry.update!(training: self)
    end
    stop_host!
    true
  end

  # The LoRA file from the ComfyUI that trained it, by SaveLoRA's naming
  # (<stem>_00001_.safetensors, the counter higher if the name was taken),
  # or nil when it can't be had (an older ComfyUI, a file moved away).
  def fetch_lora(client)
    (1..5).each do |n|
      return client.fetch("filename" => format("%s_%05d_.safetensors", stem, n), "subfolder" => "loras/baible", "type" => "output")
    rescue Comfy::Unreachable
      raise
    rescue Comfy::Error
      next
    end
    nil
  end

  # What this ComfyUI calls a LoRA baible put in its folder.
  def installed_name = "#{Comfy.config.dig(:trained_loras, :prefix).presence || 'baible'}/#{stem}.safetensors"

  # Into this ComfyUI's LoRAs, when baible has that folder. The name, or nil.
  def install(bytes)
    dir = Comfy.config.dig(:trained_loras, :dir).presence or return
    FileUtils.mkdir_p(dir)
    File.binwrite(File.join(dir, "#{stem}.safetensors"), bytes)
    installed_name
  rescue SystemCallError => e
    update!(host_note: "Couldn't put the LoRA in #{dir} (#{e.message}): download it from this run instead.")
    nil
  end

  # Trained here and not installed: as this ComfyUI lists it in its outputs
  # (README "Training"), or will.
  def local_name(client)
    client.capabilities.loras.find { |file| File.basename(file).start_with?("#{stem}_") } || expected_lora
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
