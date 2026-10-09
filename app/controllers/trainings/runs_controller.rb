# frozen_string_literal: true

# Training a kept set in ComfyUI, or a failed run again.
class Trainings::RunsController < ApplicationController
  include TrainingScoped

  def create
    @training.train!
    redirect_to entry_path(@entry, anchor: "lora"), notice: "#{@training.title} is training in ComfyUI.", status: :see_other
  end
end
