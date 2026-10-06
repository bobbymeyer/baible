# frozen_string_literal: true

# Letting a pick go: the subject (or variant) has no file until another is picked.
class PicksController < ApplicationController
  def destroy
    pick = Pick.find(params[:id])
    pick.destroy!
    redirect_to subject_path(pick.subject, anchor: "picks"), notice: "#{pick.title} has no pick now.", status: :see_other
  end
end
