# frozen_string_literal: true

# Picking the winner: it becomes the subject's (or the variant's) pick,
# with its seed and the recipe that made it.
class Candidates::PicksController < ApplicationController
  include CandidateScoped

  def create
    pick = @candidate.pick!
    redirect_to subject_path(@subject, anchor: "picks"), notice: "#{pick.title} has a new pick (seed #{pick.seed}).", status: :see_other
  end
end
