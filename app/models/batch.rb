# frozen_string_literal: true

# One round of generation for a subject or one of its variants (the target;
# docs/HANDOFF.md "Batches, candidates, picks"): the composed recipe,
# frozen when the batch starts, and its candidates. Each candidate is its
# own ComfyUI prompt with its own seed. BatchJob submits and collects
# (ComfyRun); every change refreshes the studios watching the subject.
class Batch < ApplicationRecord
  include ComfyRun

  # "scheduled": queued for the night window (NightShift), not yet let go.
  STATUSES = [ "scheduled", *ComfyRun::STATUSES ].freeze

  belongs_to :subject
  belongs_to :variant, optional: true
  has_many :candidates, -> { order(:position) }, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  after_commit :refresh_watchers

  # A new batch replaces any earlier one for the same target, except those
  # made overnight, which wait to be reviewed: the strip shows one round at
  # a time, plus the night's. The first candidate tries a seed hint when
  # there is one (the picture it starts from, or the subject's own pick for
  # a variant), so a face stays closer across variants.
  # write: let the language model (if there is one) rewrite the subject.
  # transparent: remove the background, or keep it, whatever the kind says.
  # draft: quick previews (fewer steps, smaller, cut out like the full
  # render would be), to be made properly with #refine!.
  # source: a pick to redraw from instead of starting blank (a chain):
  # { "pick_id" => n, "crop" => "head" | nil }, re-noised by denoise; it is
  # put in ComfyUI's inputs when the batch runs. Images only.
  # tonight: queue it for the night window instead (NightShift): it waits as
  # "scheduled", is made at full quality (no drafts: nobody is there to
  # choose one), and replaces nothing, as nothing replaces it but a pick.
  def self.start!(subject, variant: nil, count: Comfy.config[:candidates], write: true, transparent: nil, draft: false, source: nil,
                  denoise: nil, tonight: false)
    draft = false if tonight
    raise ArgumentError, "That variant is another subject's" if variant && variant.subject_id != subject.id

    count = count.to_i.clamp(1, 8)
    base = Random.rand(2**31)
    seeds = Array.new(count) { |i| (base + i) % 2**31 }
    from = source && Pick.find(source["pick_id"])
    hint = from ? from.seed : subject.seed_hint(variant)
    seeds[0] = hint if hint
    batch = transaction do
      subject.batches.where(variant: variant, night: false).destroy_all unless tonight
      recipe = subject.recipe(variant)
      if subject.image?
        recipe["write"] = write && Llm.enabled?
        recipe["transparent"] = transparent unless transparent.nil?
        if from
          recipe = recipe.merge("source" => { "pick_id" => from.id, "crop" => source["crop"].presence, "label" => from.title }.compact,
                                "denoise" => denoise.to_f.clamp(0.1, 1.0))
        end
        if recipe["transparent"]
          recipe["cutout"] = Cutout.label # the removal model, in ComfyUI
          recipe = Cutout.on_ground(recipe) # rendered on the ground the cut-out keys against, not white
        end
        recipe = draft_of(recipe) if draft
      end
      create!(subject: subject, variant: variant, recipe: recipe, night: tonight, status: tonight ? "scheduled" : "queued").tap do |b|
        seeds.each_with_index { |seed, i| b.candidates.create!(position: i, seed: seed) }
      end
    end
    BatchJob.perform_later(batch) unless tonight
    batch
  end

  # The night shift lets it go: into ComfyUI, as if just started.
  def release!
    raise ArgumentError, "Only a scheduled batch is let go" unless status == "scheduled"

    update!(status: "queued", released_at: Time.current)
    BatchJob.perform_later(self)
  end

  # A recipe made quick: the family's draft steps and size. The background
  # comes off a draft too, since a draft can be used as it is. What the
  # full render needs is kept.
  def self.draft_of(recipe)
    family = Comfy::Family.new(recipe["family"], recipe["model"])
    width, height = family.draft_size(recipe["width"], recipe["height"])
    recipe.merge("draft" => true, "steps" => family.draft_steps, "width" => width, "height" => height,
                 "full" => recipe.slice("width", "height", "transparent"))
  end

  def draft? = recipe["draft"] == true
  def audio? = recipe["medium"] == "audio"

  # Make one draft properly: the same prompt and seed at full size and
  # steps, starting from the draft image so it stays the same picture. A
  # new batch of one; the drafts stay on the page beside it.
  def self.refine!(candidate)
    batch = candidate.batch
    raise Refusal, "Only a draft can be made properly" unless batch.draft?
    raise Refusal, "That draft has no image yet" unless candidate.status == "done" && candidate.file.attached?

    family = Comfy::Family.new(batch.recipe["family"], batch.recipe["model"])
    recipe = batch.recipe.except("draft", "steps", "full", "workflow", "source_image").merge(batch.recipe["full"])
                  .merge("write" => false, "refines" => { "batch_id" => batch.id, "candidate_id" => candidate.id }, "denoise" => family.refine_denoise)
    refinement = transaction do
      batch.subject.batches.where(variant_id: batch.variant_id, night: false).where.not(id: batch.id).destroy_all
      create!(subject: batch.subject, variant: batch.variant, recipe: recipe).tap { |b| b.candidates.create!(position: 0, seed: candidate.seed) }
    end
    BatchJob.perform_later(refinement)
    refinement
  end

  # The drafts a refinement came from, while they're still here.
  def drafts
    Batch.find_by(id: recipe.dig("refines", "batch_id")) if recipe["refines"]
  end

  # The subject or variant the batch is for, in a sentence.
  def title = subject.title(variant)

  # What starts from an image (a refinement from its draft, a chain step
  # from another pick) has it put in ComfyUI's inputs first.
  def upload_source!(client)
    return if recipe["source_image"]

    bytes, name = source_bytes
    return unless bytes

    update!(recipe: recipe.merge("source_image" => client.upload(bytes, name)))
  end

  # [bytes, a name for ComfyUI's inputs], or nil when the batch starts blank.
  def source_bytes
    if recipe["refines"]
      source = Candidate.find_by(id: recipe.dig("refines", "candidate_id"))
      raise Comfy::Error, "The draft to refine is gone" unless source&.file&.attached?

      # As rendered, on its ground: the cut-out's colours are the render's.
      [ Cutout.opaque(source.file.download), "baible-draft-#{source.id}-#{source.seed}.png" ]
    elsif (source = recipe["source"])
      pick = Pick.find_by(id: source["pick_id"])
      raise Comfy::Error, "The picture to draw from (#{source['label'] || 'a pick'}) is gone" unless pick&.file&.attached?
      raise Comfy::Error, "#{pick.title} isn't an image to draw from" unless pick.image?

      if source["crop"] == "head"
        [ Headshot.of(pick.file.download), "baible-head-#{pick.id}-#{pick.seed}.png" ]
      else
        [ pick.file.download, "baible-from-#{pick.id}-#{pick.seed}.png" ]
      end
    end
  end

  # Where a chain step starts from, for the strip ("from Cid's head").
  def source_label
    source = recipe["source"] or return
    source["crop"] == "head" ? "from the head of #{source['label']}" : "from #{source['label']}"
  end

  # Before anything is queued: the language model's go at the subject, when
  # asked for. Every candidate then shares one prompt, so an image model
  # that caches its text encodings only encodes it once.
  def write_prompt!(llm)
    return unless recipe["write"] && !recipe.dig("parts", "written") && !recipe["writer_error"]

    update!(recipe: PromptWriter.rewrite(recipe, client: llm))
  end

  # Queue every candidate with ComfyUI, each graph built against what this
  # ComfyUI has installed. ComfyUI runs them one after another, keeping the
  # loaded model and encoded prompt between them.
  def submit!(client)
    capabilities = client.capabilities
    unless capabilities.reachable?
      raise (capabilities.offline? ? Comfy::Unreachable : Comfy::Error), capabilities.error || "ComfyUI isn't answering"
    end

    candidates.each do |candidate|
      next if candidate.comfy_prompt_id

      graph = build(seed: candidate.seed, capabilities: capabilities)
      update!(recipe: recipe.merge("workflow" => Comfy::Workflow.outline(graph))) unless recipe["workflow"]
      candidate.update!(comfy_prompt_id: client.submit(graph), status: "running")
    end
    update!(status: "running", error: nil, submitted_at: submitted_at || Time.current)
  end

  # The graph for one candidate: an image's (Comfy::Workflow) or audio's
  # (Comfy::Music). ComfyUI keeps what it saves in output/baible/.
  def build(seed:, capabilities:)
    prefix = "baible/#{subject.file_stem(variant, seed)}"
    if audio?
      Comfy::Music.build(recipe, seed: seed, prefix: prefix, capabilities: capabilities)
    else
      Comfy::Workflow.build(recipe, seed: seed, prefix: prefix, capabilities: capabilities)
    end
  end

  # Collect whatever has finished. Returns true once every candidate has.
  def collect!(client)
    candidates.reject(&:finished?).each { |candidate| candidate.collect!(client) }
    return false if candidates.reload.any? { |c| !c.finished? }

    if candidates.all? { |c| c.status == "failed" }
      fail!(candidates.first&.error || "Nothing came back")
    else
      update!(status: "done")
    end
    true
  end

  # The batch fails with its candidates still out (ComfyRun).
  def fail!(message)
    super
    candidates.reject(&:finished?).each { |c| c.update!(status: "failed", error: message) }
  end

  # When ComfyUI took it; a batch made before ComfyUI could be reached counts from when it was made.
  def comfy_started_at = submitted_at || released_at || created_at

  # Only the studio's batches reload (app/javascript/stream_actions.js), so
  # a form being typed into elsewhere on the page is left alone.
  def refresh_watchers
    Turbo::StreamsChannel.broadcast_action_to(subject, :studio, action: :reload_frame, target: "batches") if subject
  end
end
