# frozen_string_literal: true

# The studio's batches alone, for the "batches" frame to reload as files
# land (Batch#refresh_watchers).
class Subjects::PanelsController < ApplicationController
  include SubjectScoped

  def show
    render partial: "subjects/batches", locals: { subject: @subject }
  end
end
