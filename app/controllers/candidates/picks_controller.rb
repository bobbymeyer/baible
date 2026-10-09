# frozen_string_literal: true

# Picking the winner: it becomes the subject's (or the variant's) current
# pick, with its seed, the recipe that made it and who picked it. The pick
# before it stays in the history; a canon pick stays canon.
class Candidates::PicksController < ApplicationController
  include CandidateScoped

  def create
    pick = @candidate.pick!(user: Current.user)
    notice = "#{pick.title} has a new pick (seed #{pick.seed})."
    notice += " Canon is still the one approved before; approve this one to replace it." if @subject.pick_for(pick.variant) != pick
    redirect_to subject_path(@subject, anchor: "picks"), notice: notice, status: :see_other
  end
end
