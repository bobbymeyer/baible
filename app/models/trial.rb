# frozen_string_literal: true

# A test render of a learned family or workflow (docs/HANDOFF.md "Unknown
# models and new workflows"): one picture through ComfyUI, made as a batch
# is (TrialJob, ComfyRun), for a person to look at before accepting it.
class Trial < ApplicationRecord
  include ComfyRun

  PROMPT = "a red apple on a wooden table, soft daylight"

  belongs_to :learnable, polymorphic: true
  has_one_attached :image

  validates :status, inclusion: { in: STATUSES }

  after_commit -> { learnable&.refresh_watchers }

  def submit!(client)
    capabilities = client.capabilities
    raise (capabilities.offline? ? Comfy::Unreachable : Comfy::Error), capabilities.error || "ComfyUI isn't answering" unless capabilities.reachable?

    graph = learnable.trial_graph(prompt: prompt, seed: seed, prefix: "baible/trial-#{learnable_type.underscore}-#{learnable_id}-#{id}",
                                  client: client, capabilities: capabilities)
    update!(comfy_prompt_id: client.submit(graph), status: "running", error: nil, submitted_at: Time.current)
  end

  def collect!(client)
    files = client.result(comfy_prompt_id) or return false
    saved = files.find { |file| file["filename"].to_s.match?(/\.(png|jpe?g|webp)\z/i) } or return fail!("The workflow saved no picture") || true

    image.attach(io: StringIO.new(client.fetch(saved)), filename: "trial-#{id}.png", content_type: "image/png", identify: false)
    update!(status: "done", run_seconds: client.run_seconds(comfy_prompt_id))
    true
  end

  def comfy_started_at = submitted_at || created_at
end
