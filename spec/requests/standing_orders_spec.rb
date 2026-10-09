# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Standing orders", type: :request do
  let(:project) { make_project }

  it "adds one on the Overnight page, turns it off and on, and deletes it" do
    creature = project.kinds.find_by!(name: "Creature")
    post standing_orders_path, params: { standing_order: { project_id: project.id, kind_id: creature.id, action: "fill_gaps", count: 2, nightly_limit: 10 } }
    order = StandingOrder.sole
    expect(order).to have_attributes(kind: creature, count: 2, user: @user, enabled: true)
    expect(flash[:notice]).to eq("Fill the gaps for Creature in The Drowned Coast, every night.")

    get night_path
    expect(page.at("#orders").text).to include("Fill the gaps", "Creature", "Not planned yet", "2 candidates a target")

    patch standing_order_path(order), params: { standing_order: { enabled: "0" } }
    expect(order.reload.enabled).to be(false)
    delete standing_order_path(order)
    expect(StandingOrder.count).to eq(0)
  end

  it "refuses a kind or entry from another project, and training without an entry" do
    other = make_project("Elsewhere")
    post standing_orders_path, params: { standing_order: { project_id: project.id, kind_id: other.kinds.first.id, action: "fill_gaps" } }
    expect(flash[:alert]).to include("Kind must be one of the project's")
    post standing_orders_path, params: { standing_order: { project_id: project.id, action: "train" } }
    expect(flash[:alert]).to include("Entry is needed to train a LoRA")
    expect(StandingOrder.count).to eq(0)
  end
end
