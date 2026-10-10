# frozen_string_literal: true

# Work the night shift plans for itself (docs/HANDOFF.md "Standing
# orders"): once a night, at the first tick after the window opens, each
# enabled order looks at its project (or one kind of it, or one entry) and
# queues what is owed, as if someone had pressed "Queue for tonight":
#
#   fill_gaps    a batch for every target (a subject or a variant) with no pick
#   until_canon  a batch for every target with picks but none approved
#   train        a training run for an entry, once it has min_pictures canon
#                image picks that its last run didn't train on
#
# Unreviewed work never piles up: a target that still has a night batch
# (queued, made and not picked, or failed and not discarded) gets nothing
# more until it's dealt with, and an order queues at most nightly_limit
# batches. What it did is kept in report, for the Overnight page.
class StandingOrder < ApplicationRecord
  ACTIONS = {
    "fill_gaps" => "Fill the gaps",
    "until_canon" => "Keep going until canon",
    "train" => "Train when ready"
  }.freeze

  belongs_to :project
  belongs_to :kind, optional: true
  belongs_to :entry, optional: true
  belongs_to :user, optional: true

  normalizes :model, with: ->(value) { value.to_s.strip.presence }

  validates :action, inclusion: { in: ACTIONS.keys }
  validates :count, numericality: { only_integer: true, in: 1..8 }
  validates :nightly_limit, numericality: { only_integer: true, in: 1..200 }
  validates :min_pictures, numericality: { only_integer: true, in: 1..200 }
  validate :scope_is_the_projects
  validate :train_needs_an_entry

  scope :enabled, -> { where(enabled: true) }

  def label = ACTIONS.fetch(action)

  # What it covers, in words: "The Drowned Coast", "Portrait", "Cid",
  # "Cid, Portrait". Narrowed, the project goes beside it (#where).
  def scope_label = [ entry&.name, kind&.name ].compact.join(", ").presence || project.name

  def where = entry || kind ? "#{scope_label} in #{project.name}" : project.name

  # Plan tonight's share, once per night window: from the first tick after
  # the window opened. Returns the report.
  def plan!(opened_at)
    return report if planned_at && planned_at >= opened_at

    note = action == "train" ? plan_training : plan_batches
    update!(planned_at: Time.current, report: note)
    note
  end

  # The targets it looks at: every subject in scope, and each variant. A
  # sheet isn't made, only laid out, so it's never one.
  def targets
    subjects = project.subjects.includes(:kind, :variants, :picks, :batches)
    subjects = subjects.where(kind: kind) if kind
    subjects = subjects.where(entry: entry) if entry
    subjects.reject(&:sheet?).sort_by { |subject| [ subject.kind.position, subject.name.downcase ] }
            .flat_map { |subject| [ nil, *subject.variants ].map { |variant| [ subject, variant ] } }
  end

  private

  def plan_batches
    owed = targets.select { |subject, variant| owed?(subject, variant) }
    waiting = targets.count { |subject, variant| unreviewed?(subject, variant) }
    queued = owed.first(nightly_limit)
    queued.each { |subject, variant| Batch.start!(subject, variant: variant, count: count, tonight: true) }

    parts = [ "Queued #{pluralize(queued.size, 'batch')} of #{count}" ]
    parts << "#{owed.size - queued.size} more owed, over the nightly limit" if owed.size > queued.size
    parts << "#{pluralize(waiting, 'target')} still waiting for review of an earlier night's" if waiting.positive?
    parts.join("; ") + "."
  end

  def owed?(subject, variant)
    return false if unreviewed?(subject, variant)

    picks = subject.target_picks(variant)
    action == "fill_gaps" ? picks.empty? : picks.any? && picks.none?(&:canon?)
  end

  # A night batch still there: queued, made and not picked from, or failed
  # and not discarded.
  def unreviewed?(subject, variant)
    subject.batches.any? { |batch| batch.night? && batch.variant_id == variant&.id }
  end

  def plan_training
    entry.reload # its picks as they are now, not as an earlier look cached them
    canon = entry.pick_rows.filter_map { |subject, variant, _| (pick = subject.pick_for(variant)) && pick.canon? && pick.image? && pick }
    last = entry.trainings.first
    return "Waiting for #{min_pictures} canon pictures; #{entry.name} has #{canon.size}." if canon.size < min_pictures
    return "#{last.title} is still to train or training." if last && last.status.in?(%w[scheduled queued waiting running])
    if last && last.items.map { |item| item["pick_id"] }.sort == canon.map(&:id).sort
      return "Nothing new since #{last.title}: the same #{pluralize(canon.size, 'canon picture')}."
    end

    model = self.model || Comfy.config.dig(:training, :model).presence
    return "No base model to train on: set one on this order, or COMFY_TRAINING_MODEL." unless model

    run = Training.start!(entry, canon.map { |pick| { pick: pick, caption: Training.caption_for(pick) } },
                          trigger: entry.trigger_or_default, model: model, settings: {}, user: user, train: :tonight)
    "Queued #{run.title} on #{pluralize(canon.size, 'canon picture')}, after the night's generations."
  end

  def pluralize(count, word) = ActionController::Base.helpers.pluralize(count, word)

  def scope_is_the_projects
    errors.add(:kind, "must be one of the project's") if kind && kind.project_id != project_id
    errors.add(:entry, "must be one of the project's") if entry && entry.project_id != project_id
  end

  def train_needs_an_entry
    errors.add(:entry, "is needed to train a LoRA") if action == "train" && !entry
  end
end
