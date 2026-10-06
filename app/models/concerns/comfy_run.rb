# frozen_string_literal: true

# A record made in ComfyUI (a Batch's images or audio): its way
# through, as a status, and how a job (ApplicationJob#poll_comfy) marks it
# waiting for ComfyUI, failed, or out of time. The record says when ComfyUI
# took it (#comfy_started_at) and how to #submit! and #collect!.
#
#   queued    made; the job hasn't reached ComfyUI yet
#   waiting   ComfyUI couldn't be reached; the job tries again later
#   running   ComfyUI has it
#   done, failed
module ComfyRun
  extend ActiveSupport::Concern

  STATUSES = %w[queued waiting running done failed].freeze

  # How long ComfyUI gets, from when it took the work (config/comfy.yml).
  def self.timeout = Comfy.config.fetch(:timeout, 900).to_i.seconds

  def finished? = status.in?(%w[done failed])

  # Not with ComfyUI yet: to be submitted (again).
  def unsubmitted? = status.in?(%w[queued waiting])

  # ComfyUI couldn't be reached: say so, and keep everything for the retry.
  def wait!(message) = update!(status: "waiting", error: message.to_s.truncate(500))

  def fail!(message) = update!(status: "failed", error: message.to_s.truncate(500))

  # Rendering has taken too long (counted from when ComfyUI took it: a
  # record waiting for ComfyUI to come back isn't timing out).
  def timed_out?
    started = comfy_started_at
    started.present? && started < ComfyRun.timeout.ago
  end
end
