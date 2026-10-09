# frozen_string_literal: true

# Deleting a training run: its record and set go; a LoRA ComfyUI saved
# stays on ComfyUI. One still with ComfyUI is left to finish.
class TrainingsController < ApplicationController
  def destroy
    training = Training.find(params[:id])
    raise Refusal, "#{training.title} is still with ComfyUI" if training.status.in?(%w[queued waiting running])

    training.destroy!
    redirect_to entry_path(training.entry, anchor: "lora"), notice: "#{training.title} is gone.", status: :see_other
  end
end
