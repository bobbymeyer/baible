# frozen_string_literal: true

# Making a draft properly (Batch.refine!): full size and steps, from the
# draft itself.
class Candidates::RefinementsController < ApplicationController
  include CandidateScoped

  def create
    Batch.refine!(@candidate)
    redirect_to subject_path(@subject, anchor: "batches"), notice: "Making seed #{@candidate.seed} properly.", status: :see_other
  end
end
