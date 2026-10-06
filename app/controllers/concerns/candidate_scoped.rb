# frozen_string_literal: true

# Loads a candidate in the URL (candidate_id) and the subject it's for.
module CandidateScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_candidate

    rescue_from Refusal do |refusal|
      redirect_to subject_path(@subject, anchor: "batches"), alert: refusal.message, status: :see_other
    end
  end

  private

  def set_candidate
    @candidate = Candidate.find(params[:candidate_id])
    @subject = @candidate.subject
  end
end
