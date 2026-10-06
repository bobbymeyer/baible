# frozen_string_literal: true

# Loads the project in the URL (project_id) for a controller nested under it.
module ProjectScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_project
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
