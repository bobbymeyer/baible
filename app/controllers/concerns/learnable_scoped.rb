# frozen_string_literal: true

# Loads the learned family or workflow in the URL, for a controller nested
# under either.
module LearnableScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_learnable
  end

  private

  def set_learnable
    @learnable = params[:learned_family_id] ? LearnedFamily.find(params[:learned_family_id]) : LearnedWorkflow.find(params[:learned_workflow_id])
  end
end
