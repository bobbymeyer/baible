# frozen_string_literal: true

# An entry's LoRA training sets (docs/HANDOFF.md "The LoRA loop"): choosing
# the pictures and their captions (new), keeping the set and training it in
# ComfyUI or not (create), and the runs alone for their frame (index).
class Entries::TrainingsController < ApplicationController
  include EntryScoped

  def index
    render partial: "entries/trainings", locals: { entry: @entry }
  end

  def new
    @rows = @entry.pick_rows
    @model = default_model
  end

  def create
    chosen = params.fetch(:items, {}).to_unsafe_h.select { |_, row| row["use"] == "1" }
    picks = Pick.where(id: chosen.keys).includes(:subject).index_by { |pick| pick.id.to_s }
    rows = chosen.filter_map do |id, row|
      pick = picks[id]
      { pick: pick, caption: row["caption"] } if pick && pick.subject.entry_id == @entry.id && pick.image?
    end
    raise Refusal, "Choose at least one picture for the set" if rows.empty?

    training = Training.start!(@entry, rows, trigger: params[:trigger].presence || @entry.trigger_or_default,
                               model: params[:model].presence || default_model, settings: params.fetch(:settings, {}).permit(*Training::SETTINGS),
                               user: Current.user, train: { "1" => :now, "tonight" => :tonight }[params[:train]])
    notice = { "set" => "#{training.title} kept: #{training.items.size} pictures.",
               "scheduled" => "#{training.title} will train tonight, after the night's generations." }
               .fetch(training.status, "#{training.title} is training in ComfyUI.")
    redirect_to entry_path(@entry, anchor: "lora"), notice: notice, status: :see_other
  end

  private

  # The model config/comfy.yml names for training (an SDXL checkpoint), else
  # the one most of its standing pictures were made with, else the default.
  def default_model
    return Comfy.config.dig(:training, :model) if Comfy.config.dig(:training, :model).present?

    standing = @entry.pick_rows.map { |subject, variant, _| subject.pick_for(variant) }.compact
    standing.filter_map { |pick| pick.recipe["model"].presence }.tally.max_by(&:last)&.first || Comfy.config[:model]
  end
end
