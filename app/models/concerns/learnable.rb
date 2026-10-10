# frozen_string_literal: true

# What a learned family and a learned workflow share (docs/HANDOFF.md
# "Unknown models and new workflows"): proposed by the language model (or
# edited by a person), checked against the server, tried in a test render
# (Trial), and accepted by a person before baible uses it. Until accepted it
# is never used for a batch. Editing it sends it back to proposed.
#
#   asking    the language model is writing it (LearnJob)
#   proposed  it passed the server's checks; waiting for a trial and a person
#   accepted  in use
#   failed    the language model couldn't make one that passes (error says why)
module Learnable
  extend ActiveSupport::Concern

  STATUSES = %w[asking proposed accepted failed].freeze

  included do
    belongs_to :user, optional: true
    belongs_to :accepted_by, class_name: "User", optional: true
    has_many :trials, -> { order(:id) }, as: :learnable, dependent: :destroy

    validates :status, inclusion: { in: STATUSES }

    scope :accepted, -> { where(status: "accepted") }

    after_commit :refresh_watchers
  end

  def accepted? = status == "accepted"

  def latest_trial = trials.last

  # In use, once a test render came out (a person has looked at it).
  def accept!(user)
    raise Refusal, "Only a proposal that passed the server's checks can be accepted" unless status == "proposed"
    raise Refusal, "Try it first: a test render has to come out before it's accepted" unless latest_trial&.status == "done"

    update!(status: "accepted", accepted_by: user, accepted_at: Time.current)
  end

  # What was asked and answered, kept short, for the page.
  def note!(line)
    update_column(:log, [ log, line.to_s.truncate(4000) ].compact.join("\n\n").last(20_000))
  end

  def refresh_watchers
    Turbo::StreamsChannel.broadcast_action_to(:learning, action: :reload_frame, target: "learning")
  end
end
