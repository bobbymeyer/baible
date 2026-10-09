# frozen_string_literal: true

# Approving a pick as its target's canon (create), in place of any other,
# and taking that back (destroy). Who approved it, and when, is kept.
class Picks::CanonsController < ApplicationController
  include PickScoped

  def create
    @pick.approve!(Current.user)
    redirect_to subject_path(@pick.subject, anchor: "picks"), notice: "Seed #{@pick.seed} is #{@pick.title}'s canon.", status: :see_other
  end

  def destroy
    @pick.unapprove!
    redirect_to subject_path(@pick.subject, anchor: "picks"), notice: "#{@pick.title} has no canon now.", status: :see_other
  end
end
