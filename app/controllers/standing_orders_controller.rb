# frozen_string_literal: true

# Standing orders (docs/HANDOFF.md "Standing orders"), kept on the Overnight
# page: adding one, switching it on or off, and deleting it. Planning them is
# the night shift's (NightShift.plan!).
class StandingOrdersController < ApplicationController
  def create
    order = StandingOrder.new(order_params.merge(user: Current.user))
    order.project = Project.find_by(id: order_params[:project_id])
    if order.save
      redirect_to night_path(anchor: "orders"), notice: "#{order.label} for #{order.where}, every night.", status: :see_other
    else
      redirect_to night_path(anchor: "orders"), alert: order.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def update
    order = StandingOrder.find(params[:id])
    order.update!(enabled: params.expect(standing_order: [ :enabled ])[:enabled] == "1")
    redirect_to night_path(anchor: "orders"), notice: "#{order.label} for #{order.where} is #{order.enabled? ? 'on' : 'off'}.", status: :see_other
  end

  def destroy
    order = StandingOrder.find(params[:id])
    order.destroy!
    redirect_to night_path(anchor: "orders"), notice: "#{order.label} for #{order.where} is gone.", status: :see_other
  end

  private

  def order_params
    params.expect(standing_order: [ :project_id, :kind_id, :entry_id, :action, :count, :nightly_limit, :min_pictures, :model ])
  end
end
