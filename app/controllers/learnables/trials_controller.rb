# frozen_string_literal: true

# A test render of a learned family or workflow, through ComfyUI.
class Learnables::TrialsController < ApplicationController
  include LearnableScoped

  def create
    raise Refusal, "Only a proposal that passed the server's checks can be tried" unless @learnable.status.in?(%w[proposed accepted])

    trial = @learnable.trials.create!(prompt: params[:prompt].presence || Trial::PROMPT, seed: Random.rand(2**31))
    TrialJob.perform_later(trial)
    redirect_to learning_path(anchor: helpers.dom_id(@learnable)), notice: "Trying it: the picture appears here when ComfyUI is done.", status: :see_other
  end
end
