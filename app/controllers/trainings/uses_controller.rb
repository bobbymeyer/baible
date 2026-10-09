# frozen_string_literal: true

# The entry using a run's LoRA (create), or none (destroy). Only a finished
# run has one.
class Trainings::UsesController < ApplicationController
  include TrainingScoped

  def create
    raise Refusal, "#{@training.title} has no LoRA yet" unless @training.status == "done" && @training.lora

    @entry.update!(training: @training)
    redirect_to entry_path(@entry, anchor: "lora"), notice: "#{@entry.name} uses #{@training.title}'s LoRA.", status: :see_other
  end

  def destroy
    @entry.update!(training: nil) if @entry.training_id == @training.id
    redirect_to entry_path(@entry, anchor: "lora"), notice: "#{@entry.name} uses no trained LoRA now.", status: :see_other
  end
end
