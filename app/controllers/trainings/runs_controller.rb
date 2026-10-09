# frozen_string_literal: true

# Training a kept set in ComfyUI, or a failed run again: now, or tonight
# (tonight=1, NightShift); and taking a scheduled run off tonight's queue
# (destroy), back to a kept set.
class Trainings::RunsController < ApplicationController
  include TrainingScoped

  def create
    if params[:tonight] == "1"
      @training.schedule!
      notice = "#{@training.title} will train tonight, after the night's generations."
    else
      @training.train!
      notice = "#{@training.title} is training in ComfyUI."
    end
    redirect_back_or_to entry_path(@entry, anchor: "lora"), notice: notice, status: :see_other
  end

  def destroy
    @training.unschedule!
    redirect_back_or_to entry_path(@entry, anchor: "lora"), notice: "#{@training.title} won't train tonight.", status: :see_other
  end
end
