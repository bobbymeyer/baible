# frozen_string_literal: true

# Loads the training run in the URL (training_id), its entry and project,
# for a controller nested under it.
module TrainingScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_training
  end

  private

  def set_training
    @training = Training.find(params[:training_id])
    @entry = @training.entry
    @project = @entry.project
  end
end
