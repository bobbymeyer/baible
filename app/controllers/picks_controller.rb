# frozen_string_literal: true

# Letting a pick go from its target's history. A canon pick is unapproved
# first (Pick#let_go! refuses); when the current one goes, the newest left
# takes its place.
class PicksController < ApplicationController
  def destroy
    pick = Pick.find(params[:id])
    pick.let_go!
    standing = pick.subject.pick_for(pick.variant)
    notice = standing ? "Let go. #{pick.title} is back to seed #{standing.seed}." : "Let go. #{pick.title} has no pick now."
    redirect_to subject_path(pick.subject, anchor: "picks"), notice: notice, status: :see_other
  end
end
