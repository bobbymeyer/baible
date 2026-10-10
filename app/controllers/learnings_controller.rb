# frozen_string_literal: true

# Models and workflows (docs/HANDOFF.md "Unknown models and new
# workflows"): the models ComfyUI has and how each runs, the families and
# workflows the language model has written, with their trials. frame=1
# renders the frame alone, for it to reload as things change.
class LearningsController < ApplicationController
  def show
    @families = LearnedFamily.includes(trials: { image_attachment: :blob }).order(:label)
    @workflows = LearnedWorkflow.includes(:kinds, trials: { image_attachment: :blob }).order(:name)
    render partial: "learnings/frame" if params[:frame]
  end
end
