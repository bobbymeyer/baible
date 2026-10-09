# frozen_string_literal: true

# Use this again: a pick from the history becomes its target's current pick.
class Picks::CurrentsController < ApplicationController
  include PickScoped

  def create
    @pick.make_current!
    redirect_to subject_path(@pick.subject, anchor: "picks"), notice: "#{@pick.title} uses seed #{@pick.seed} again.", status: :see_other
  end
end
