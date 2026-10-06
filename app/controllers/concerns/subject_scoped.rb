# frozen_string_literal: true

# Loads the subject in the URL (subject_id), and its project, for a
# controller nested under it.
module SubjectScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_subject
  end

  private

  def set_subject
    @subject = Subject.find(params[:subject_id])
    @project = @subject.project
  end
end
