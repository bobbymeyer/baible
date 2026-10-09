# frozen_string_literal: true

# Overnight (docs/HANDOFF.md "Overnight"): what's queued for tonight's
# window, and what the night made, for review in the morning: the night's
# batches still waiting for a pick (or failed), and training runs that
# finished in the last day.
class NightsController < ApplicationController
  def show
    @window = NightShift.window
    @orders = StandingOrder.includes(:project, :kind, :entry).order(:id)
    @order = StandingOrder.new(project: Project.order(:name).first)
    @queued_batches = NightShift.queued_batches.includes(:variant, :candidates, subject: %i[project kind])
    @queued_trainings = NightShift.queued_trainings.includes(entry: :project)
    @made = Batch.where(night: true).where.not(status: "scheduled").order(:id)
                 .includes(:variant, subject: %i[project kind], candidates: { file_attachment: :blob })
    @trained = Training.where(status: %w[done failed]).where(updated_at: 1.day.ago..).order(updated_at: :desc).includes(entry: :project)
  end
end
